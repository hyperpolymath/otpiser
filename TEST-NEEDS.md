# TEST-NEEDS.md — otpiser

## CRG Grade: C — ACHIEVED 2026-04-04

## Current Test State

| Category | Count | Notes |
|----------|-------|-------|
| Integration tests (Rust) | 2 | `tests/integration_test.rs` compiled binaries |
| Verification tests | Unit-level | `verification/tests/` directory present |
| FFI tests | Present | `src/interface/ffi/test/` |

## What's Covered

- [x] Dual integration test builds (debug + release)
- [x] FFI verification layer
- [x] Cargo test harness

## Still Missing (for CRG B+)

- [ ] Property-based testing (proptest)
- [ ] Fuzzing targets
- [ ] Benchmarking suite
- [ ] CI integration tests

## Run Tests

```bash
cd /var/mnt/eclipse/repos/otpiser && cargo test
```
