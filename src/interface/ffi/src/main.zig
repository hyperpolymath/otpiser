// Otpiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions.
// Provides supervision tree construction, validation, and Elixir code emission.
//
// SPDX-License-Identifier: PMPL-1.0-or-later

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "Otpiser built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/interface/abi/Types.idr)
//==============================================================================

/// Result codes (must match Idris2 Result type)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    invalid_strategy = 5,
    malformed_tree = 6,
};

/// OTP supervision strategies (must match Idris2 SupervisorStrategy type)
pub const SupervisorStrategy = enum(u32) {
    one_for_one = 0,
    one_for_all = 1,
    rest_for_one = 2,
};

/// Child restart types (must match Idris2 ChildRestartType)
pub const ChildRestartType = enum(u32) {
    permanent = 0,
    transient = 1,
    temporary = 2,
};

/// Node type discriminator
pub const NodeType = enum(u32) {
    supervisor = 0,
    worker = 1,
};

/// A node in the supervision tree (internal representation).
/// Supervisors have children; workers are leaves.
const TreeNode = struct {
    node_type: NodeType,
    name: []const u8,
    // Supervisor-specific fields
    strategy: SupervisorStrategy,
    max_restarts: u32,
    max_seconds: u32,
    // Worker-specific fields
    module_name: []const u8,
    restart_type: ChildRestartType,
    shutdown_ms: u32,
    // Tree structure
    children: std.ArrayList(*TreeNode),
    allocator: std.mem.Allocator,

    fn deinit(self: *TreeNode) void {
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }
};

/// Library handle (opaque to C callers).
/// Holds the allocator and all constructed tree nodes.
const OtpiserHandle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    nodes: std.ArrayList(*TreeNode),

    fn deinit(self: *OtpiserHandle) void {
        for (self.nodes.items) |node| {
            node.deinit();
            self.allocator.destroy(node);
        }
        self.nodes.deinit();
    }
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the otpiser library.
/// Returns a handle, or null on failure.
export fn otpiser_init() ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(OtpiserHandle) catch {
        setError("Failed to allocate otpiser handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .nodes = std.ArrayList(*TreeNode).init(allocator),
    };

    clearError();
    return @ptrCast(handle);
}

/// Free the otpiser library handle and all associated tree nodes.
export fn otpiser_free(handle: ?*anyopaque) void {
    const h = getHandle(handle) orelse return;
    const allocator = h.allocator;

    h.deinit();
    h.initialized = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Supervision Tree Construction
//==============================================================================

/// Create a new supervisor node.
/// Returns a node handle for use with otpiser_add_child.
export fn otpiser_create_supervisor(
    handle: ?*anyopaque,
    name_ptr: ?[*:0]const u8,
    strategy: u32,
    max_restarts: u32,
    max_seconds: u32,
) ?*anyopaque {
    const h = getHandle(handle) orelse {
        setError("Null otpiser handle");
        return null;
    };

    const name = if (name_ptr) |p| std.mem.span(p) else {
        setError("Null supervisor name");
        return null;
    };

    if (strategy > 2) {
        setError("Invalid supervision strategy (must be 0, 1, or 2)");
        return null;
    }

    if (max_seconds == 0) {
        setError("max_seconds must be > 0");
        return null;
    }

    const node = h.allocator.create(TreeNode) catch {
        setError("Failed to allocate supervisor node");
        return null;
    };

    node.* = .{
        .node_type = .supervisor,
        .name = name,
        .strategy = @enumFromInt(strategy),
        .max_restarts = max_restarts,
        .max_seconds = max_seconds,
        .module_name = "",
        .restart_type = .permanent,
        .shutdown_ms = 0xFFFFFFFF,
        .children = std.ArrayList(*TreeNode).init(h.allocator),
        .allocator = h.allocator,
    };

    h.nodes.append(node) catch {
        h.allocator.destroy(node);
        setError("Failed to track supervisor node");
        return null;
    };

    clearError();
    return @ptrCast(node);
}

/// Create a worker (GenServer) child node.
export fn otpiser_create_worker(
    handle: ?*anyopaque,
    child_id_ptr: ?[*:0]const u8,
    module_ptr: ?[*:0]const u8,
    restart_type: u32,
    shutdown_ms: u32,
) ?*anyopaque {
    const h = getHandle(handle) orelse {
        setError("Null otpiser handle");
        return null;
    };

    const child_id = if (child_id_ptr) |p| std.mem.span(p) else {
        setError("Null child ID");
        return null;
    };

    const module_name = if (module_ptr) |p| std.mem.span(p) else {
        setError("Null module name");
        return null;
    };

    if (restart_type > 2) {
        setError("Invalid restart type (must be 0, 1, or 2)");
        return null;
    }

    const node = h.allocator.create(TreeNode) catch {
        setError("Failed to allocate worker node");
        return null;
    };

    node.* = .{
        .node_type = .worker,
        .name = child_id,
        .strategy = .one_for_one,
        .max_restarts = 0,
        .max_seconds = 0,
        .module_name = module_name,
        .restart_type = @enumFromInt(restart_type),
        .shutdown_ms = shutdown_ms,
        .children = std.ArrayList(*TreeNode).init(h.allocator),
        .allocator = h.allocator,
    };

    h.nodes.append(node) catch {
        h.allocator.destroy(node);
        setError("Failed to track worker node");
        return null;
    };

    clearError();
    return @ptrCast(node);
}

/// Add a child to a supervisor node.
export fn otpiser_add_child(
    handle: ?*anyopaque,
    supervisor: ?*anyopaque,
    child: ?*anyopaque,
) Result {
    _ = getHandle(handle) orelse {
        setError("Null otpiser handle");
        return .null_pointer;
    };

    const sup: *TreeNode = @ptrCast(@alignCast(supervisor orelse {
        setError("Null supervisor node");
        return .null_pointer;
    }));

    const ch: *TreeNode = @ptrCast(@alignCast(child orelse {
        setError("Null child node");
        return .null_pointer;
    }));

    if (sup.node_type != .supervisor) {
        setError("Cannot add child to a worker node");
        return .invalid_param;
    }

    sup.children.append(ch) catch {
        setError("Failed to add child to supervisor");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

//==============================================================================
// OTP Code Emission (stubs — implementation in Phase 1)
//==============================================================================

/// Generate Elixir supervision tree code from the constructed tree.
export fn otpiser_emit_elixir(
    handle: ?*anyopaque,
    tree_root: ?*anyopaque,
    out_dir_ptr: ?[*:0]const u8,
) Result {
    _ = getHandle(handle) orelse {
        setError("Null otpiser handle");
        return .null_pointer;
    };
    _ = tree_root orelse {
        setError("Null tree root");
        return .null_pointer;
    };
    _ = out_dir_ptr orelse {
        setError("Null output directory");
        return .null_pointer;
    };

    // TODO: Implement Elixir code emission
    setError("Elixir code emission not yet implemented");
    return .@"error";
}

/// Generate mix.exs project file.
export fn otpiser_emit_mix(
    handle: ?*anyopaque,
    app_name_ptr: ?[*:0]const u8,
    out_dir_ptr: ?[*:0]const u8,
) Result {
    _ = getHandle(handle) orelse return .null_pointer;
    _ = app_name_ptr orelse return .null_pointer;
    _ = out_dir_ptr orelse return .null_pointer;

    // TODO: Implement mix.exs generation
    setError("mix.exs generation not yet implemented");
    return .@"error";
}

/// Generate ExUnit test scaffolding.
export fn otpiser_emit_tests(
    handle: ?*anyopaque,
    tree_root: ?*anyopaque,
    out_dir_ptr: ?[*:0]const u8,
) Result {
    _ = getHandle(handle) orelse return .null_pointer;
    _ = tree_root orelse return .null_pointer;
    _ = out_dir_ptr orelse return .null_pointer;

    // TODO: Implement test scaffolding generation
    setError("Test generation not yet implemented");
    return .@"error";
}

//==============================================================================
// Tree Validation
//==============================================================================

/// Validate a supervision tree for correctness.
export fn otpiser_validate_tree(
    handle: ?*anyopaque,
    tree_root: ?*anyopaque,
) Result {
    _ = getHandle(handle) orelse {
        setError("Null otpiser handle");
        return .null_pointer;
    };

    const root: *TreeNode = @ptrCast(@alignCast(tree_root orelse {
        setError("Null tree root");
        return .null_pointer;
    }));

    // Root must be a supervisor
    if (root.node_type != .supervisor) {
        setError("Tree root must be a supervisor node");
        return .malformed_tree;
    }

    // Supervisor must have at least one child
    if (root.children.items.len == 0) {
        setError("Supervisor must have at least one child");
        return .malformed_tree;
    }

    // Validate recursively
    if (!validateNodeRecursive(root)) {
        return .malformed_tree;
    }

    clearError();
    return .ok;
}

/// Recursive tree validation helper.
fn validateNodeRecursive(node: *TreeNode) bool {
    if (node.name.len == 0) {
        setError("Node has empty name");
        return false;
    }

    if (node.node_type == .supervisor) {
        if (node.max_seconds == 0) {
            setError("Supervisor max_seconds must be > 0");
            return false;
        }
        for (node.children.items) |child| {
            if (!validateNodeRecursive(child)) return false;
        }
    }

    return true;
}

/// Get a human-readable description of the last validation error.
export fn otpiser_validation_error(handle: ?*anyopaque) ?[*:0]const u8 {
    _ = getHandle(handle) orelse return null;
    return otpiser_last_error();
}

//==============================================================================
// Tree Serialisation
//==============================================================================

/// Get the required buffer size for serialising a tree.
export fn otpiser_serialized_size(handle: ?*anyopaque, tree_root: ?*anyopaque) u32 {
    _ = getHandle(handle) orelse return 0;
    const root: *TreeNode = @ptrCast(@alignCast(tree_root orelse return 0));
    return countNodes(root) * 32; // Each serialized node is 32 bytes
}

/// Serialise a supervision tree to a flat buffer.
export fn otpiser_serialize_tree(
    handle: ?*anyopaque,
    tree_root: ?*anyopaque,
    out_buf: ?*anyopaque,
    buf_len: u32,
) u32 {
    _ = getHandle(handle) orelse return 0;
    _ = tree_root orelse return 0;
    _ = out_buf orelse return 0;
    _ = buf_len;

    // TODO: Implement tree serialisation
    return 0;
}

/// Count total nodes in a tree
fn countNodes(node: *TreeNode) u32 {
    var count: u32 = 1;
    for (node.children.items) |child| {
        count += countNodes(child);
    }
    return count;
}

//==============================================================================
// String Operations
//==============================================================================

/// Free a string allocated by the library
export fn otpiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message.
/// Returns null if no error.
export fn otpiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn otpiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn otpiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn otpiser_is_initialized(handle: ?*anyopaque) u32 {
    const h = getHandle(handle) orelse return 0;
    return if (h.initialized) 1 else 0;
}

/// Internal helper: safely cast opaque handle to OtpiserHandle
fn getHandle(handle: ?*anyopaque) ?*OtpiserHandle {
    const ptr = handle orelse return null;
    return @ptrCast(@alignCast(ptr));
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    try std.testing.expect(otpiser_is_initialized(handle) == 1);
}

test "create supervisor and worker" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "MyApp.Supervisor", 0, 3, 5);
    try std.testing.expect(sup != null);

    const worker = otpiser_create_worker(handle, "db_pool", "MyApp.DBPool", 0, 5000);
    try std.testing.expect(worker != null);

    const result = otpiser_add_child(handle, sup, worker);
    try std.testing.expectEqual(Result.ok, result);
}

test "validate valid tree" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Root", 0, 3, 5);
    const worker = otpiser_create_worker(handle, "worker1", "Worker", 0, 5000);
    _ = otpiser_add_child(handle, sup, worker);

    const result = otpiser_validate_tree(handle, sup);
    try std.testing.expectEqual(Result.ok, result);
}

test "validate empty supervisor fails" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Empty", 0, 3, 5);
    const result = otpiser_validate_tree(handle, sup);
    try std.testing.expectEqual(Result.malformed_tree, result);
}

test "invalid strategy rejected" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Bad", 99, 3, 5);
    try std.testing.expect(sup == null);
}

test "error handling" {
    const result = otpiser_validate_tree(null, null);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = otpiser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = otpiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}
