// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for otpiser.
// Rust-side types mirroring the Idris2 ABI formal definitions.
// The Idris2 proofs guarantee correctness; this module provides runtime types
// for supervision tree construction, strategy selection, and child spec management.

/// OTP supervision strategies.
/// Mirrors `Otpiser.ABI.Types.SupervisorStrategy` from Idris2.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum SupervisorStrategy {
    /// Restart only the failed child. Use for independent services.
    OneForOne = 0,
    /// Restart all children when any fails. Use for tightly coupled groups.
    OneForAll = 1,
    /// Restart failed child and all started after it. Use for ordered dependencies.
    RestForOne = 2,
}

/// Child restart types.
/// Mirrors `Otpiser.ABI.Types.ChildRestartType` from Idris2.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum ChildRestartType {
    /// Always restart (normal or abnormal termination).
    Permanent = 0,
    /// Only restart on abnormal termination.
    Transient = 1,
    /// Never restart.
    Temporary = 2,
}

/// Shutdown behaviour for a child process.
/// Mirrors `Otpiser.ABI.Types.ShutdownType` from Idris2.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShutdownType {
    /// Wait up to N milliseconds, then force kill.
    Timeout(u32),
    /// Immediate brutal kill.
    BrutalKill,
    /// Wait indefinitely (for supervisors draining children).
    Infinity,
}

/// Restart intensity configuration.
/// Mirrors `Otpiser.ABI.Types.RestartIntensity` from Idris2.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RestartIntensity {
    /// Maximum restart count in the time window.
    pub max_restarts: u32,
    /// Time window in seconds (must be > 0).
    pub max_seconds: u32,
}

impl Default for RestartIntensity {
    /// OTP default: 3 restarts in 5 seconds.
    fn default() -> Self {
        Self {
            max_restarts: 3,
            max_seconds: 5,
        }
    }
}

/// Child specification for a supervised process.
/// Mirrors `Otpiser.ABI.Types.ChildSpec` from Idris2.
#[derive(Debug, Clone)]
pub struct ChildSpec {
    /// Unique child identifier.
    pub child_id: String,
    /// Elixir module name for the child process.
    pub start_module: String,
    /// Arguments passed to the child's start function.
    pub start_args: Vec<String>,
    /// How the child should be restarted.
    pub restart_type: ChildRestartType,
    /// How long to wait for graceful shutdown.
    pub shutdown: ShutdownType,
    /// Whether this child is a worker or a supervisor.
    pub child_type: ChildType,
}

/// Whether a child is a worker or a supervisor.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum ChildType {
    Worker = 0,
    Supervisor = 1,
}

/// A node in the supervision tree.
/// Mirrors `Otpiser.ABI.Types.ProcessTree` from Idris2.
#[derive(Debug, Clone)]
pub enum ProcessTree {
    /// A supervisor node with strategy, intensity, and children.
    SupervisorNode {
        name: String,
        strategy: SupervisorStrategy,
        intensity: RestartIntensity,
        children: Vec<ProcessTree>,
    },
    /// A worker leaf node backed by a GenServer or GenStateMachine.
    WorkerNode {
        spec: ChildSpec,
    },
}

impl ProcessTree {
    /// Count total nodes in the tree.
    pub fn size(&self) -> usize {
        match self {
            ProcessTree::WorkerNode { .. } => 1,
            ProcessTree::SupervisorNode { children, .. } => {
                1 + children.iter().map(|c| c.size()).sum::<usize>()
            }
        }
    }

    /// Count worker nodes only.
    pub fn worker_count(&self) -> usize {
        match self {
            ProcessTree::WorkerNode { .. } => 1,
            ProcessTree::SupervisorNode { children, .. } => {
                children.iter().map(|c| c.worker_count()).sum()
            }
        }
    }

    /// Depth of the supervision tree.
    pub fn depth(&self) -> usize {
        match self {
            ProcessTree::WorkerNode { .. } => 0,
            ProcessTree::SupervisorNode { children, .. } => {
                1 + children.iter().map(|c| c.depth()).max().unwrap_or(0)
            }
        }
    }
}

/// FFI result codes.
/// Mirrors `Otpiser.ABI.Types.Result` from Idris2.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum FfiResult {
    Ok = 0,
    Error = 1,
    InvalidParam = 2,
    OutOfMemory = 3,
    NullPointer = 4,
    InvalidStrategy = 5,
    MalformedTree = 6,
}
