<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->
# TOPOLOGY.md — otpiser

## Purpose

otpiser generates fault-tolerant OTP supervision trees for Erlang/Elixir systems. It reads a service topology description from an `otpiser.toml` manifest and emits Erlang/Elixir modules with correctly structured supervisor trees, child specifications, restart strategies, and Zig FFI bridges for native integration. otpiser targets engineers who want the reliability guarantees of the OTP supervision model without hand-authoring the boilerplate of nested supervisors and child specs.

## Module Map

```
otpiser/
├── src/
│   ├── main.rs                    # CLI entry point (clap): init, validate, generate, build, run, info
│   ├── lib.rs                     # Library API
│   ├── manifest/mod.rs            # otpiser.toml parser
│   ├── codegen/mod.rs             # OTP/Erlang wrapper, Zig FFI bridge, C header generation
│   └── ...                        # [WIP] supervision strategy modules
├── examples/                      # Worked examples
├── verification/                  # Proof harnesses
├── container/                     # Stapeln container ecosystem
└── .machine_readable/             # A2ML metadata
```

## Data Flow

```
otpiser.toml manifest
        │
   ┌────▼────┐
   │ Manifest │  parse + validate service topology and restart strategy definitions
   │  Parser  │
   └────┬────┘
        │  validated OTP topology config
   ┌────▼────┐
   │ Analyser │  resolve supervision hierarchy, validate restart intensities
   └────┬────┘
        │  intermediate representation
   ┌────▼────┐
   │ Codegen  │  emit generated/otpiser/ (Erlang/Elixir supervisors, Zig FFI, C headers)
   └────┬────┘
        │  OTP supervision tree artifacts
   ┌────▼────┐
   │  OTP VM  │  run fault-tolerant supervision hierarchy on BEAM
   └─────────┘
```
