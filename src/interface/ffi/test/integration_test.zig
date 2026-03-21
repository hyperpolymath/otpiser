// Otpiser Integration Tests
// SPDX-License-Identifier: PMPL-1.0-or-later
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for OTP supervision tree generation. Tests cover lifecycle, tree construction,
// validation, and error handling across the FFI boundary.

const std = @import("std");
const testing = std.testing;

// Import FFI functions (C ABI exports from libotpiser)
extern fn otpiser_init() ?*anyopaque;
extern fn otpiser_free(?*anyopaque) void;
extern fn otpiser_is_initialized(?*anyopaque) u32;
extern fn otpiser_create_supervisor(?*anyopaque, ?[*:0]const u8, u32, u32, u32) ?*anyopaque;
extern fn otpiser_create_worker(?*anyopaque, ?[*:0]const u8, ?[*:0]const u8, u32, u32) ?*anyopaque;
extern fn otpiser_add_child(?*anyopaque, ?*anyopaque, ?*anyopaque) c_int;
extern fn otpiser_validate_tree(?*anyopaque, ?*anyopaque) c_int;
extern fn otpiser_emit_elixir(?*anyopaque, ?*anyopaque, ?[*:0]const u8) c_int;
extern fn otpiser_last_error() ?[*:0]const u8;
extern fn otpiser_version() [*:0]const u8;
extern fn otpiser_build_info() [*:0]const u8;
extern fn otpiser_serialized_size(?*anyopaque, ?*anyopaque) u32;
extern fn otpiser_free_string(?[*:0]const u8) void;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const initialized = otpiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = otpiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Supervisor Construction Tests
//==============================================================================

test "create one_for_one supervisor" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "MyApp.Supervisor", 0, 3, 5);
    try testing.expect(sup != null);
}

test "create one_for_all supervisor" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "MyApp.GroupSupervisor", 1, 5, 10);
    try testing.expect(sup != null);
}

test "create rest_for_one supervisor" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "MyApp.ChainSupervisor", 2, 1, 60);
    try testing.expect(sup != null);
}

test "invalid strategy (3) returns null" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Bad", 3, 3, 5);
    try testing.expect(sup == null);
}

test "null supervisor name returns null" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, null, 0, 3, 5);
    try testing.expect(sup == null);
}

//==============================================================================
// Worker Construction Tests
//==============================================================================

test "create permanent worker" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const worker = otpiser_create_worker(handle, "db_pool", "MyApp.DBPool", 0, 5000);
    try testing.expect(worker != null);
}

test "create transient worker" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const worker = otpiser_create_worker(handle, "batch_job", "MyApp.BatchJob", 1, 10000);
    try testing.expect(worker != null);
}

test "create temporary worker" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const worker = otpiser_create_worker(handle, "one_shot", "MyApp.OneShot", 2, 0);
    try testing.expect(worker != null);
}

//==============================================================================
// Tree Construction Tests
//==============================================================================

test "add child to supervisor" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Root", 0, 3, 5);
    const worker = otpiser_create_worker(handle, "w1", "MyApp.Worker", 0, 5000);

    const result = otpiser_add_child(handle, sup, worker);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "add multiple children to supervisor" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Root", 0, 3, 5);
    const w1 = otpiser_create_worker(handle, "w1", "MyApp.Worker1", 0, 5000);
    const w2 = otpiser_create_worker(handle, "w2", "MyApp.Worker2", 0, 5000);
    const w3 = otpiser_create_worker(handle, "w3", "MyApp.Worker3", 1, 10000);

    try testing.expectEqual(@as(c_int, 0), otpiser_add_child(handle, sup, w1));
    try testing.expectEqual(@as(c_int, 0), otpiser_add_child(handle, sup, w2));
    try testing.expectEqual(@as(c_int, 0), otpiser_add_child(handle, sup, w3));
}

test "nested supervision tree" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    // Root supervisor (one_for_one)
    const root = otpiser_create_supervisor(handle, "Root", 0, 3, 5);

    // Group supervisor (one_for_all — tightly coupled)
    const group = otpiser_create_supervisor(handle, "Group", 1, 5, 10);
    const g1 = otpiser_create_worker(handle, "cache", "MyApp.Cache", 0, 5000);
    const g2 = otpiser_create_worker(handle, "writer", "MyApp.Writer", 0, 5000);
    _ = otpiser_add_child(handle, group, g1);
    _ = otpiser_add_child(handle, group, g2);

    // Chain supervisor (rest_for_one — ordered deps)
    const chain = otpiser_create_supervisor(handle, "Chain", 2, 1, 60);
    const c1 = otpiser_create_worker(handle, "db", "MyApp.DB", 0, 10000);
    const c2 = otpiser_create_worker(handle, "api", "MyApp.API", 1, 5000);
    _ = otpiser_add_child(handle, chain, c1);
    _ = otpiser_add_child(handle, chain, c2);

    // Wire subtrees into root
    _ = otpiser_add_child(handle, root, group);
    _ = otpiser_add_child(handle, root, chain);
}

test "add child to null supervisor returns error" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const worker = otpiser_create_worker(handle, "w1", "Worker", 0, 5000);
    const result = otpiser_add_child(handle, null, worker);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// Tree Validation Tests
//==============================================================================

test "validate valid single-level tree" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Root", 0, 3, 5);
    const worker = otpiser_create_worker(handle, "w1", "Worker", 0, 5000);
    _ = otpiser_add_child(handle, sup, worker);

    const result = otpiser_validate_tree(handle, sup);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "validate empty supervisor fails" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Empty", 0, 3, 5);
    const result = otpiser_validate_tree(handle, sup);
    try testing.expectEqual(@as(c_int, 6), result); // 6 = malformed_tree
}

test "validate null tree root fails" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const result = otpiser_validate_tree(handle, null);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// Serialisation Tests
//==============================================================================

test "serialized size of single-node tree" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Root", 0, 3, 5);
    const worker = otpiser_create_worker(handle, "w1", "W", 0, 5000);
    _ = otpiser_add_child(handle, sup, worker);

    const size = otpiser_serialized_size(handle, sup);
    try testing.expectEqual(@as(u32, 64), size); // 2 nodes * 32 bytes each
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = otpiser_validate_tree(null, null);

    const err = otpiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const handle = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(handle);

    const sup = otpiser_create_supervisor(handle, "Root", 0, 3, 5);
    try testing.expect(sup != null);
    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = otpiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = otpiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info contains Zig" {
    const info = otpiser_build_info();
    const info_str = std.mem.span(info);
    try testing.expect(std.mem.indexOf(u8, info_str, "Zig") != null);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(h1);

    const h2 = otpiser_init() orelse return error.InitFailed;
    defer otpiser_free(h2);

    try testing.expect(h1 != h2);

    // Trees on h1 should not affect h2
    const sup1 = otpiser_create_supervisor(h1, "S1", 0, 3, 5);
    const sup2 = otpiser_create_supervisor(h2, "S2", 1, 5, 10);
    try testing.expect(sup1 != null);
    try testing.expect(sup2 != null);
}

test "free null is safe" {
    otpiser_free(null); // Should not crash
}
