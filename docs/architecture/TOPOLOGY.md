<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->
# otpiser — TOPOLOGY

## Module Map

```
otpiser/
├── src/
│   ├── main.rs                     # CLI entry point (clap subcommands)
│   ├── lib.rs                      # Library API (load → validate → generate)
│   ├── manifest/
│   │   └── mod.rs                  # TOML manifest parser (otpiser.toml)
│   ├── codegen/
│   │   └── mod.rs                  # Elixir/OTP code generation engine
│   ├── abi/
│   │   └── mod.rs                  # Rust-side ABI types (mirrors Idris2)
│   ├── interface/
│   │   ├── abi/                    # Idris2 ABI — formal verification layer
│   │   │   ├── Types.idr           # SupervisorStrategy, ChildSpec, RestartIntensity,
│   │   │   │                       # GenServerCallback, ProcessTree, Result, Handle
│   │   │   ├── Layout.idr          # Supervision tree node memory layout proofs
│   │   │   └── Foreign.idr         # FFI declarations for tree generation + OTP emission
│   │   ├── ffi/                    # Zig FFI — C-ABI bridge
│   │   │   ├── build.zig           # Build config (shared + static lib)
│   │   │   ├── src/main.zig        # FFI implementation (lifecycle, operations, NIF bridge)
│   │   │   └── test/
│   │   │       └── integration_test.zig  # Cross-boundary integration tests
│   │   └── generated/
│   │       └── abi/                # Auto-generated C headers from Idris2
│   ├── definitions/                # Domain type definitions
│   ├── errors/                     # Error types and diagnostics
│   ├── aspects/
│   │   ├── security/               # Security aspects (BEAM VM hardening)
│   │   ├── observability/          # Telemetry and tracing
│   │   └── integrity/              # Data integrity checks
│   ├── contracts/                  # Design-by-contract assertions
│   ├── core/                       # Core algorithms (tree computation)
│   └── bridges/                    # Cross-iser bridge modules
├── tests/                          # Rust integration tests
├── examples/                       # Example manifests and generated output
├── container/                      # Stapeln container ecosystem
├── verification/                   # Formal verification artifacts
├── docs/
│   ├── architecture/               # This file, threat model
│   ├── theory/                     # OTP theory, supervision patterns
│   ├── practice/                   # User manuals, guides
│   ├── attribution/                # Citations, maintainers
│   └── legal/                      # License exhibits
└── .machine_readable/              # All machine-readable metadata (6a2, policies, etc.)
```

## Data Flow

```
otpiser.toml (user manifest)
    │
    ▼
┌──────────────────┐
│  Manifest Parser │  src/manifest/mod.rs
│  (TOML → Rust)   │  Parses service descriptions, SLA, strategy hints
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│  Tree Planner    │  src/core/
│  (Graph → Tree)  │  Builds dependency graph, computes supervision topology
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│  Strategy Engine │  src/codegen/mod.rs
│  (Assign OTP     │  Selects one_for_one / one_for_all / rest_for_one
│   strategies)    │  Calculates max_restarts, child spec ordering
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│  Codegen Engine  │  src/codegen/mod.rs
│  (Tree → Elixir) │  Emits Application, Supervisor, GenServer, GenStateMachine
└──────┬───────────┘
       │
       ├──► lib/my_app/application.ex     (OTP Application)
       ├──► lib/my_app/supervisor.ex      (Root Supervisor)
       ├──► lib/my_app/workers/*.ex       (GenServer / GenStateMachine modules)
       ├──► lib/my_app/health.ex          (Health check GenServer)
       ├──► config/config.exs             (Application config)
       ├──► mix.exs                       (Project definition)
       └──► test/**/*_test.exs            (ExUnit test scaffolding)
```

## Supervision Tree Model

OTPiser generates trees following this hierarchy:

```
Application
└── RootSupervisor (strategy from manifest)
    ├── ServiceGroupSupervisor_A (one_for_all — tightly coupled)
    │   ├── GenServer: ServiceA_Primary
    │   ├── GenServer: ServiceA_Cache
    │   └── GenServer: ServiceA_Writer
    ├── ServiceGroupSupervisor_B (rest_for_one — ordered deps)
    │   ├── GenServer: DB_Pool
    │   ├── GenServer: Query_Cache (depends on DB_Pool)
    │   └── GenServer: API_Handler (depends on Query_Cache)
    ├── DynamicSupervisor: ConnectionPool
    │   └── (workers spawned on demand)
    ├── Task.Supervisor: AsyncJobs
    └── GenServer: HealthMonitor
```

## Key Interfaces

| Interface | Location | Purpose |
|-----------|----------|---------|
| CLI → Manifest | `main.rs` → `manifest/mod.rs` | Parse `otpiser.toml` |
| Manifest → Codegen | `manifest::Manifest` struct | Validated service description |
| Codegen → Elixir | `codegen/mod.rs` → templates | Generate `.ex` files |
| Idris2 ABI → Zig FFI | `Types.idr` → `main.zig` | Verified type bridge |
| Zig FFI → BEAM NIF | `main.zig` → Erlang NIF API | Performance-critical paths |

## Cross-iser Integration Points

- **iseriser**: Can scaffold new otpiser-style projects
- **chapeliser**: Distributed computing — otpiser supervises Chapel workers
- **verisimiser**: Database layer — otpiser supervises VeriSimDB connections
- **Burble**: Voice platform — otpiser generates supervision trees for call handling
