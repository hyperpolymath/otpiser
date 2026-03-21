// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for otpiser.
// Validates manifest parsing, codegen output, and supervision tree structure.

use otpiser::manifest;
use tempfile::TempDir;

/// Helper: create a temporary directory and initialise a manifest in it.
fn init_in_tempdir() -> (TempDir, String) {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let path = tmp.path().to_str().unwrap().to_string();
    manifest::init_manifest(&path).expect("init_manifest failed");
    (tmp, path)
}

/// Helper: write a custom manifest TOML to a temp directory and return path.
fn write_manifest(dir: &TempDir, content: &str) -> String {
    let manifest_path = dir.path().join("otpiser.toml");
    std::fs::write(&manifest_path, content).expect("Failed to write manifest");
    manifest_path.to_str().unwrap().to_string()
}

// ---------------------------------------------------------------------------
// test_init_creates_manifest
// ---------------------------------------------------------------------------

#[test]
fn test_init_creates_manifest() {
    let (tmp, _path) = init_in_tempdir();
    let manifest_path = tmp.path().join("otpiser.toml");
    assert!(manifest_path.exists(), "otpiser.toml should exist after init");

    // Verify the manifest can be loaded and validated.
    let m = manifest::load_manifest(manifest_path.to_str().unwrap())
        .expect("Should load generated manifest");
    manifest::validate(&m).expect("Generated manifest should be valid");

    // Verify essential fields from the template.
    assert_eq!(m.workload.name, "my_app");
    assert_eq!(m.workload.entry, "MyApp.Application");
    assert_eq!(m.workload.strategy, "one_for_one");
}

#[test]
fn test_init_refuses_overwrite() {
    let (tmp, path) = init_in_tempdir();
    // Second init should fail because the file already exists.
    let result = manifest::init_manifest(&path);
    assert!(result.is_err(), "Should refuse to overwrite existing manifest");
    // Original file should still be intact.
    let _m = manifest::load_manifest(
        tmp.path().join("otpiser.toml").to_str().unwrap(),
    )
    .expect("Original manifest should still be loadable");
}

// ---------------------------------------------------------------------------
// test_generate_produces_elixir_modules
// ---------------------------------------------------------------------------

#[test]
fn test_generate_produces_elixir_modules() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "my_app"
entry = "MyApp.Application"
strategy = "one_for_one"

[data]
input-type = "Request"
output-type = "Response"

[options]
flags = []
generate-tests = true
generate-docker = false

[[supervisors]]
name = "main"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "cache"
type = "worker"
module = "Cache"
restart = "permanent"

[[supervisors.children]]
name = "task-runner"
type = "worker"
restart = "transient"
"#;

    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");
    manifest::validate(&m).expect("Manifest should be valid");

    // Generate into a subdirectory.
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    // Verify mix.exs exists.
    assert!(output_dir.join("mix.exs").exists(), "mix.exs should exist");

    // Verify Application module exists.
    assert!(
        output_dir.join("lib/my_app/application.ex").exists(),
        "application.ex should exist"
    );

    // Verify supervisor module exists.
    assert!(
        output_dir.join("lib/my_app/main_supervisor.ex").exists(),
        "main_supervisor.ex should exist"
    );

    // Verify worker modules exist.
    assert!(
        output_dir.join("lib/my_app/cache.ex").exists(),
        "cache.ex worker should exist"
    );
    assert!(
        output_dir.join("lib/my_app/task_runner.ex").exists(),
        "task_runner.ex worker should exist"
    );

    // Verify test files exist.
    assert!(
        output_dir.join("test/test_helper.exs").exists(),
        "test_helper.exs should exist"
    );
    assert!(
        output_dir.join("test/my_app_test.exs").exists(),
        "my_app_test.exs should exist"
    );

    // Verify supervision tree diagram.
    assert!(
        output_dir.join("SUPERVISION_TREE.txt").exists(),
        "SUPERVISION_TREE.txt should exist"
    );

    // Verify .formatter.exs.
    assert!(
        output_dir.join(".formatter.exs").exists(),
        ".formatter.exs should exist"
    );
}

#[test]
fn test_generated_mix_exs_content() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "payment_gateway"
entry = "PaymentGateway.Application"
strategy = "one_for_one"

[data]
input-type = "PaymentRequest"
output-type = "PaymentResult"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    let mix_content =
        std::fs::read_to_string(output_dir.join("mix.exs")).expect("Should read mix.exs");
    assert!(
        mix_content.contains("app: :payment_gateway"),
        "mix.exs should contain the app name atom"
    );
    assert!(
        mix_content.contains("PaymentGateway.Application"),
        "mix.exs should reference the application module"
    );
    assert!(
        mix_content.contains("PaymentGateway.MixProject"),
        "mix.exs should define the MixProject module"
    );
}

#[test]
fn test_generated_application_references_supervisors() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "my_app"
entry = "MyApp.Application"
strategy = "rest_for_one"

[data]
input-type = "Request"
output-type = "Response"

[[supervisors]]
name = "workers"
strategy = "one_for_all"
max-restarts = 5
max-seconds = 10

[[supervisors]]
name = "support"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    let app_content = std::fs::read_to_string(output_dir.join("lib/my_app/application.ex"))
        .expect("Should read application.ex");
    assert!(
        app_content.contains("MyApp.WorkersSupervisor"),
        "Application should reference WorkersSupervisor"
    );
    assert!(
        app_content.contains("MyApp.SupportSupervisor"),
        "Application should reference SupportSupervisor"
    );
    assert!(
        app_content.contains("strategy: :rest_for_one"),
        "Application should use root strategy from manifest"
    );
}

// ---------------------------------------------------------------------------
// test_supervision_tree_structure
// ---------------------------------------------------------------------------

#[test]
fn test_supervision_tree_structure() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "my_app"
entry = "MyApp.Application"
strategy = "one_for_one"

[data]
input-type = "Request"
output-type = "Response"

[[supervisors]]
name = "main"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "db-pool"
type = "supervisor"
strategy = "one_for_all"
restart = "permanent"

[[supervisors.children]]
name = "cache"
type = "worker"
module = "Cache"
restart = "permanent"

[[supervisors.children]]
name = "metrics"
type = "worker"
restart = "transient"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");
    manifest::validate(&m).expect("Manifest should be valid");

    // Verify the parsed supervision tree structure.
    assert_eq!(m.supervisors.len(), 1, "Should have one root supervisor");
    let main_sup = &m.supervisors[0];
    assert_eq!(main_sup.name, "main");
    assert_eq!(main_sup.strategy, "one_for_one");
    assert_eq!(main_sup.max_restarts, 3);
    assert_eq!(main_sup.max_seconds, 5);
    assert_eq!(main_sup.children.len(), 3, "Main supervisor should have 3 children");

    // Verify child types.
    assert_eq!(main_sup.children[0].child_type, "supervisor");
    assert_eq!(main_sup.children[0].name, "db-pool");
    assert_eq!(
        main_sup.children[0].strategy.as_deref(),
        Some("one_for_all")
    );

    assert_eq!(main_sup.children[1].child_type, "worker");
    assert_eq!(main_sup.children[1].name, "cache");
    assert_eq!(main_sup.children[1].module.as_deref(), Some("Cache"));

    assert_eq!(main_sup.children[2].child_type, "worker");
    assert_eq!(main_sup.children[2].name, "metrics");
    assert_eq!(main_sup.children[2].restart, "transient");

    // Verify generated supervisor module contains the strategy.
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    let sup_content =
        std::fs::read_to_string(output_dir.join("lib/my_app/main_supervisor.ex"))
            .expect("Should read main_supervisor.ex");
    assert!(
        sup_content.contains("strategy: :one_for_one"),
        "Supervisor should use one_for_one strategy"
    );
    assert!(
        sup_content.contains("max_restarts: 3"),
        "Supervisor should set max_restarts"
    );
    assert!(
        sup_content.contains("max_seconds: 5"),
        "Supervisor should set max_seconds"
    );

    // Verify the diagram was generated.
    let diagram = std::fs::read_to_string(output_dir.join("SUPERVISION_TREE.txt"))
        .expect("Should read SUPERVISION_TREE.txt");
    assert!(
        diagram.contains("MainSupervisor"),
        "Diagram should reference MainSupervisor"
    );
    assert!(
        diagram.contains("Cache"),
        "Diagram should reference Cache worker"
    );
}

// ---------------------------------------------------------------------------
// test_all_strategies_generate
// ---------------------------------------------------------------------------

#[test]
fn test_all_strategies_generate() {
    let strategies = ["one_for_one", "one_for_all", "rest_for_one"];

    for strategy in &strategies {
        let tmp = TempDir::new().expect("Failed to create temp dir");
        let manifest_toml = format!(
            r#"
[workload]
name = "strat_test"
entry = "StratTest.Application"
strategy = "{strategy}"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "root"
strategy = "{strategy}"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "worker-a"
type = "worker"
restart = "permanent"
"#
        );

        let manifest_path = write_manifest(&tmp, &manifest_toml);
        let m = manifest::load_manifest(&manifest_path)
            .unwrap_or_else(|e| panic!("Failed to parse manifest for strategy {}: {}", strategy, e));
        manifest::validate(&m)
            .unwrap_or_else(|e| panic!("Validation failed for strategy {}: {}", strategy, e));

        let output_dir = tmp.path().join("output");
        otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
            .unwrap_or_else(|e| panic!("Codegen failed for strategy {}: {}", strategy, e));

        // Verify the strategy appears in the generated supervisor.
        let sup_content = std::fs::read_to_string(output_dir.join("lib/strat_test/root_supervisor.ex"))
            .unwrap_or_else(|e| panic!("Failed to read supervisor for {}: {}", strategy, e));
        let expected_strategy = format!("strategy: :{}", strategy);
        assert!(
            sup_content.contains(&expected_strategy),
            "Generated supervisor for {} should contain '{}'",
            strategy,
            expected_strategy
        );

        // Verify application module references the supervisor.
        let app_content = std::fs::read_to_string(output_dir.join("lib/strat_test/application.ex"))
            .unwrap_or_else(|e| panic!("Failed to read application.ex for {}: {}", strategy, e));
        assert!(
            app_content.contains("StratTest.RootSupervisor"),
            "Application should reference RootSupervisor for strategy {}",
            strategy
        );

        // Verify worker was generated.
        assert!(
            output_dir.join("lib/strat_test/worker_a.ex").exists(),
            "worker_a.ex should exist for strategy {}",
            strategy
        );
    }
}

// ---------------------------------------------------------------------------
// test_invalid_strategy_rejected
// ---------------------------------------------------------------------------

#[test]
fn test_invalid_strategy_rejected() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "bad_app"
entry = "BadApp.Application"
strategy = "invalid_strategy"

[data]
input-type = "In"
output-type = "Out"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");
    let result = manifest::validate(&m);
    assert!(result.is_err(), "Invalid strategy should fail validation");
}

#[test]
fn test_invalid_child_type_rejected() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "bad_app"
entry = "BadApp.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "main"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "broken"
type = "unknown_type"
restart = "permanent"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");
    let result = manifest::validate(&m);
    assert!(result.is_err(), "Invalid child type should fail validation");
}

// ---------------------------------------------------------------------------
// test_module_name_derivation
// ---------------------------------------------------------------------------

#[test]
fn test_module_name_derivation() {
    assert_eq!(manifest::to_module_name("worker-pool"), "WorkerPool");
    assert_eq!(manifest::to_module_name("cache"), "Cache");
    assert_eq!(manifest::to_module_name("db_pool"), "DbPool");
    assert_eq!(manifest::to_module_name("my-great-worker"), "MyGreatWorker");
}

#[test]
fn test_atom_name_derivation() {
    assert_eq!(manifest::to_atom_name("worker-pool"), "worker_pool");
    assert_eq!(manifest::to_atom_name("cache"), "cache");
    assert_eq!(manifest::to_atom_name("my-app"), "my_app");
}

// ---------------------------------------------------------------------------
// test_no_supervisors_generates_default
// ---------------------------------------------------------------------------

#[test]
fn test_no_supervisors_generates_default() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "minimal_app"
entry = "MinimalApp.Application"
strategy = "one_for_one"

[data]
input-type = "Request"
output-type = "Response"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");
    manifest::validate(&m).expect("Manifest should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    // When no supervisors are defined, a default supervisor.ex should be generated.
    assert!(
        output_dir.join("lib/minimal_app/supervisor.ex").exists(),
        "Default supervisor.ex should exist when no supervisors defined"
    );
    assert!(
        output_dir.join("lib/minimal_app/application.ex").exists(),
        "application.ex should always exist"
    );

    let sup_content = std::fs::read_to_string(output_dir.join("lib/minimal_app/supervisor.ex"))
        .expect("Should read supervisor.ex");
    assert!(
        sup_content.contains("MinimalApp.Supervisor"),
        "Default supervisor should use the root module name"
    );
}

// ---------------------------------------------------------------------------
// test_restart_types_in_child_specs
// ---------------------------------------------------------------------------

#[test]
fn test_restart_types_in_child_specs() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "restart_test"
entry = "RestartTest.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "main"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "always-up"
type = "worker"
restart = "permanent"

[[supervisors.children]]
name = "crash-ok"
type = "worker"
restart = "transient"

[[supervisors.children]]
name = "fire-and-forget"
type = "worker"
restart = "temporary"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");
    manifest::validate(&m).expect("Manifest should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    let sup_content =
        std::fs::read_to_string(output_dir.join("lib/restart_test/main_supervisor.ex"))
            .expect("Should read main_supervisor.ex");

    // Transient and temporary children should have explicit restart type in their specs.
    assert!(
        sup_content.contains("restart: :transient"),
        "Transient child should have explicit restart spec"
    );
    assert!(
        sup_content.contains("restart: :temporary"),
        "Temporary child should have explicit restart spec"
    );
}
