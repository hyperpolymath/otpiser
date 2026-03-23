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
    assert!(
        manifest_path.exists(),
        "otpiser.toml should exist after init"
    );

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
    assert!(
        result.is_err(),
        "Should refuse to overwrite existing manifest"
    );
    // Original file should still be intact.
    let _m = manifest::load_manifest(tmp.path().join("otpiser.toml").to_str().unwrap())
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
    assert_eq!(
        main_sup.children.len(),
        3,
        "Main supervisor should have 3 children"
    );

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

    let sup_content = std::fs::read_to_string(output_dir.join("lib/my_app/main_supervisor.ex"))
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
        let m = manifest::load_manifest(&manifest_path).unwrap_or_else(|e| {
            panic!("Failed to parse manifest for strategy {}: {}", strategy, e)
        });
        manifest::validate(&m)
            .unwrap_or_else(|e| panic!("Validation failed for strategy {}: {}", strategy, e));

        let output_dir = tmp.path().join("output");
        otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
            .unwrap_or_else(|e| panic!("Codegen failed for strategy {}: {}", strategy, e));

        // Verify the strategy appears in the generated supervisor.
        let sup_content =
            std::fs::read_to_string(output_dir.join("lib/strat_test/root_supervisor.ex"))
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

// ===========================================================================
// Point-to-point tests: each supervision strategy generates correct Elixir
// ===========================================================================

#[test]
fn test_one_for_one_strategy_generates_correct_elixir() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "p2p_ofo"
entry = "P2pOfo.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "core"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "alpha"
type = "worker"
restart = "permanent"

[[supervisors.children]]
name = "beta"
type = "worker"
restart = "transient"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/p2p_ofo/core_supervisor.ex"))
        .expect("read supervisor");
    assert!(
        sup.contains("strategy: :one_for_one"),
        "Strategy must be one_for_one"
    );
    assert!(sup.contains("max_restarts: 3"), "Max restarts must be 3");
    // one_for_one: each child listed independently.
    assert!(
        sup.contains("P2pOfo.Alpha"),
        "Alpha worker must be in child specs"
    );
    assert!(
        sup.contains("P2pOfo.Beta"),
        "Beta worker must be in child specs"
    );
}

#[test]
fn test_one_for_all_strategy_generates_correct_elixir() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "p2p_ofa"
entry = "P2pOfa.Application"
strategy = "one_for_all"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "coupled"
strategy = "one_for_all"
max-restarts = 10
max-seconds = 60

[[supervisors.children]]
name = "db-conn"
type = "worker"
restart = "permanent"

[[supervisors.children]]
name = "cache-layer"
type = "worker"
restart = "permanent"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/p2p_ofa/coupled_supervisor.ex"))
        .expect("read supervisor");
    assert!(
        sup.contains("strategy: :one_for_all"),
        "Strategy must be one_for_all"
    );
    assert!(sup.contains("max_restarts: 10"), "Max restarts must be 10");
    assert!(sup.contains("max_seconds: 60"), "Max seconds must be 60");
}

#[test]
fn test_rest_for_one_strategy_generates_correct_elixir() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "p2p_rfo"
entry = "P2pRfo.Application"
strategy = "rest_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "pipeline"
strategy = "rest_for_one"
max-restarts = 5
max-seconds = 10

[[supervisors.children]]
name = "producer"
type = "worker"
restart = "permanent"

[[supervisors.children]]
name = "transformer"
type = "worker"
restart = "permanent"

[[supervisors.children]]
name = "consumer"
type = "worker"
restart = "transient"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/p2p_rfo/pipeline_supervisor.ex"))
        .expect("read supervisor");
    assert!(
        sup.contains("strategy: :rest_for_one"),
        "Strategy must be rest_for_one"
    );
    // Children must be in order (rest_for_one is order-dependent).
    let producer_pos = sup.find("P2pRfo.Producer").expect("Producer in output");
    let transformer_pos = sup
        .find("P2pRfo.Transformer")
        .expect("Transformer in output");
    let consumer_pos = sup.find("P2pRfo.Consumer").expect("Consumer in output");
    assert!(
        producer_pos < transformer_pos,
        "Producer before Transformer"
    );
    assert!(
        transformer_pos < consumer_pos,
        "Transformer before Consumer"
    );
}

// ===========================================================================
// End-to-end tests: full pipeline from manifest to all generated files
// ===========================================================================

#[test]
fn test_end_to_end_full_pipeline() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "order_service"
entry = "OrderService.Application"
strategy = "one_for_one"

[data]
input-type = "OrderRequest"
output-type = "OrderResult"

[options]
flags = ["health-checks", "telemetry"]
generate-tests = true
generate-docker = false

[[supervisors]]
name = "processing"
strategy = "one_for_all"
max-restarts = 5
max-seconds = 10

[[supervisors.children]]
name = "order-validator"
type = "worker"
restart = "permanent"

[[supervisors.children]]
name = "payment-processor"
type = "worker"
restart = "permanent"

[[supervisors]]
name = "monitoring"
strategy = "one_for_one"
max-restarts = 10
max-seconds = 30

[[supervisors.children]]
name = "health-checker"
type = "worker"
restart = "transient"

[[supervisors.children]]
name = "metrics-collector"
type = "worker"
restart = "temporary"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse manifest");
    manifest::validate(&m).expect("Manifest should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    // Verify all expected files exist.
    let expected_files = vec![
        "mix.exs",
        ".formatter.exs",
        "SUPERVISION_TREE.txt",
        "lib/order_service/application.ex",
        "lib/order_service/processing_supervisor.ex",
        "lib/order_service/monitoring_supervisor.ex",
        "lib/order_service/order_validator.ex",
        "lib/order_service/payment_processor.ex",
        "lib/order_service/health_checker.ex",
        "lib/order_service/metrics_collector.ex",
        "test/test_helper.exs",
        "test/order_service_test.exs",
    ];
    for file in &expected_files {
        assert!(
            output_dir.join(file).exists(),
            "Expected file should exist: {}",
            file
        );
    }

    // Verify mix.exs references the correct app and module.
    let mix = std::fs::read_to_string(output_dir.join("mix.exs")).expect("read mix.exs");
    assert!(mix.contains("app: :order_service"));
    assert!(mix.contains("OrderService.Application"));
    assert!(mix.contains("OrderService.MixProject"));

    // Verify application.ex references both supervisors.
    let app = std::fs::read_to_string(output_dir.join("lib/order_service/application.ex"))
        .expect("read application.ex");
    assert!(app.contains("OrderService.ProcessingSupervisor"));
    assert!(app.contains("OrderService.MonitoringSupervisor"));

    // Verify test file uses ExUnit.
    let test =
        std::fs::read_to_string(output_dir.join("test/order_service_test.exs")).expect("read test");
    assert!(test.contains("use ExUnit.Case"));
    assert!(test.contains("OrderService.Application"));
}

#[test]
fn test_end_to_end_minimal_no_supervisors() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "bare_bones"
entry = "BareBones.Application"
strategy = "one_for_one"

[data]
input-type = "Msg"
output-type = "Reply"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("Should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    // Must have mix.exs, application.ex, default supervisor, diagram.
    // Note: without explicit [options] section, generate-tests defaults to false
    // because the Options struct uses #[derive(Default)] when the whole section is absent.
    assert!(output_dir.join("mix.exs").exists());
    assert!(output_dir.join("lib/bare_bones/application.ex").exists());
    assert!(output_dir.join("lib/bare_bones/supervisor.ex").exists());
    assert!(output_dir.join("SUPERVISION_TREE.txt").exists());
    assert!(output_dir.join(".formatter.exs").exists());

    // Default supervisor should reference BareBones.Supervisor module.
    let sup = std::fs::read_to_string(output_dir.join("lib/bare_bones/supervisor.ex"))
        .expect("read supervisor.ex");
    assert!(sup.contains("BareBones.Supervisor"));
}

// ===========================================================================
// Edge case tests
// ===========================================================================

#[test]
fn test_deeply_nested_supervisors_three_levels() {
    // Note: otpiser's manifest uses [[supervisors]] as flat top-level defs,
    // and children of type "supervisor" represent nesting. The codegen produces
    // a child spec with type: :supervisor. We test that 3+ supervisor children
    // parse and generate correctly.
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "deep_app"
entry = "DeepApp.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "level1"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "level2-a"
type = "supervisor"
strategy = "one_for_all"
restart = "permanent"

[[supervisors.children]]
name = "level2-b"
type = "supervisor"
strategy = "rest_for_one"
restart = "permanent"

[[supervisors.children]]
name = "leaf-worker"
type = "worker"
restart = "permanent"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("Should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/deep_app/level1_supervisor.ex"))
        .expect("read supervisor");

    // Both child supervisors should appear with type: :supervisor.
    assert!(
        sup.contains("type: :supervisor"),
        "Child supervisors should have type: :supervisor"
    );
    assert!(
        sup.contains("DeepApp.Level2A"),
        "Level2A supervisor child in specs"
    );
    assert!(
        sup.contains("DeepApp.Level2B"),
        "Level2B supervisor child in specs"
    );
    assert!(sup.contains("DeepApp.LeafWorker"), "LeafWorker in specs");
}

#[test]
fn test_supervisor_with_no_children() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "empty_sup"
entry = "EmptySup.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "vacant"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("Should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/empty_sup/vacant_supervisor.ex"))
        .expect("read supervisor");
    assert!(
        sup.contains("children = []"),
        "Empty supervisor should have empty children list"
    );
    assert!(
        sup.contains("strategy: :one_for_one"),
        "Strategy should still be set"
    );
}

#[test]
fn test_all_restart_types_permanent() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "restart_perm"
entry = "RestartPerm.Application"
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
name = "perm-worker"
type = "worker"
restart = "permanent"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("Should be valid");
    assert_eq!(m.supervisors[0].children[0].restart, "permanent");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/restart_perm/main_supervisor.ex"))
        .expect("read");
    // Permanent workers use simplified spec (no explicit restart atom).
    assert!(
        sup.contains("RestartPerm.PermWorker"),
        "Worker module referenced"
    );
}

#[test]
fn test_all_restart_types_transient() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "restart_trans"
entry = "RestartTrans.Application"
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
name = "trans-worker"
type = "worker"
restart = "transient"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("Should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/restart_trans/main_supervisor.ex"))
        .expect("read");
    assert!(
        sup.contains("restart: :transient"),
        "Transient restart must be explicit"
    );
}

#[test]
fn test_all_restart_types_temporary() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "restart_temp"
entry = "RestartTemp.Application"
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
name = "temp-worker"
type = "worker"
restart = "temporary"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("Should be valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/restart_temp/main_supervisor.ex"))
        .expect("read");
    assert!(
        sup.contains("restart: :temporary"),
        "Temporary restart must be explicit"
    );
}

#[test]
fn test_max_restarts_boundary_zero() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "boundary_app"
entry = "BoundaryApp.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "strict"
strategy = "one_for_one"
max-restarts = 0
max-seconds = 1
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("Zero max-restarts is valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/boundary_app/strict_supervisor.ex"))
        .expect("read");
    assert!(
        sup.contains("max_restarts: 0"),
        "Zero restarts should be in output"
    );
}

#[test]
fn test_max_restarts_boundary_high() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "high_restart"
entry = "HighRestart.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "generous"
strategy = "one_for_one"
max-restarts = 1000
max-seconds = 3600
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    manifest::validate(&m).expect("High values are valid");

    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(output_dir.join("lib/high_restart/generous_supervisor.ex"))
        .expect("read");
    assert!(sup.contains("max_restarts: 1000"));
    assert!(sup.contains("max_seconds: 3600"));
}

#[test]
fn test_max_seconds_zero_rejected() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "bad_seconds"
entry = "BadSeconds.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "broken"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 0
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let result = manifest::validate(&m);
    assert!(result.is_err(), "max-seconds = 0 should fail validation");
}

#[test]
fn test_invalid_restart_type_rejected() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "bad_restart"
entry = "BadRestart.Application"
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
type = "worker"
restart = "always"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let result = manifest::validate(&m);
    assert!(
        result.is_err(),
        "Invalid restart type 'always' should fail validation"
    );
}

#[test]
fn test_invalid_flag_rejected() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "bad_flags"
entry = "BadFlags.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[options]
flags = ["nonexistent-flag"]
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let result = manifest::validate(&m);
    assert!(result.is_err(), "Unknown flag should fail validation");
}

// ===========================================================================
// Aspect tests: code quality of generated output
// ===========================================================================

#[test]
fn test_generated_elixir_has_proper_camelcase_module_naming() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "name-test-app"
entry = "NameTestApp.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "my-cool-supervisor"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "http-request-handler"
type = "worker"
restart = "permanent"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let sup = std::fs::read_to_string(
        output_dir.join("lib/name_test_app/my_cool_supervisor_supervisor.ex"),
    )
    .expect("read supervisor");
    // Module name should be CamelCase.
    assert!(
        sup.contains("NameTestApp.MyCoolSupervisorSupervisor"),
        "Supervisor module uses CamelCase"
    );

    let worker =
        std::fs::read_to_string(output_dir.join("lib/name_test_app/http_request_handler.ex"))
            .expect("read worker");
    assert!(
        worker.contains("NameTestApp.HttpRequestHandler"),
        "Worker module uses CamelCase"
    );
}

#[test]
fn test_mix_exs_references_correct_application_module() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "mix_ref_test"
entry = "MixRefTest.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let mix = std::fs::read_to_string(output_dir.join("mix.exs")).expect("read mix.exs");
    // mod: {MixRefTest.Application, []} must appear.
    assert!(
        mix.contains("MixRefTest.Application"),
        "mix.exs must reference the Application module"
    );
    // app atom must match.
    assert!(
        mix.contains("app: :mix_ref_test"),
        "mix.exs must have correct app atom"
    );
    // MixProject module naming.
    assert!(
        mix.contains("defmodule MixRefTest.MixProject do"),
        "MixProject module definition"
    );
}

#[test]
fn test_supervision_tree_diagram_is_valid_ascii() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "diagram_test"
entry = "DiagramTest.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[[supervisors]]
name = "alpha"
strategy = "one_for_all"
max-restarts = 5
max-seconds = 10

[[supervisors.children]]
name = "worker-one"
type = "worker"
restart = "permanent"

[[supervisors.children]]
name = "worker-two"
type = "worker"
restart = "transient"

[[supervisors]]
name = "beta"
strategy = "rest_for_one"
max-restarts = 3
max-seconds = 5

[[supervisors.children]]
name = "worker-three"
type = "worker"
restart = "temporary"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let diagram =
        std::fs::read_to_string(output_dir.join("SUPERVISION_TREE.txt")).expect("read diagram");

    // Must contain the header.
    assert!(
        diagram.contains("Supervision Tree: diagram_test"),
        "Header present"
    );
    // Must contain both supervisors.
    assert!(
        diagram.contains("AlphaSupervisor"),
        "Alpha supervisor in diagram"
    );
    assert!(
        diagram.contains("BetaSupervisor"),
        "Beta supervisor in diagram"
    );
    // Must contain workers.
    assert!(diagram.contains("WorkerOne"), "WorkerOne in diagram");
    assert!(diagram.contains("WorkerTwo"), "WorkerTwo in diagram");
    assert!(diagram.contains("WorkerThree"), "WorkerThree in diagram");
    // Must contain legend.
    assert!(diagram.contains("Legend:"), "Legend section present");
    // Must be valid UTF-8 with only printable characters, newlines, and common punctuation.
    // The diagram uses em-dash (—) which is valid UTF-8 but not ASCII.
    assert!(
        diagram.chars().all(|c| c.is_ascii() || c == '\u{2014}'),
        "Diagram should only contain ASCII and em-dash characters"
    );
    // Must contain strategy annotations.
    assert!(
        diagram.contains("one_for_all"),
        "Strategy annotation in diagram"
    );
    assert!(
        diagram.contains("rest_for_one"),
        "Strategy annotation in diagram"
    );
}

#[test]
fn test_generated_test_files_use_exunit() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "exunit_check"
entry = "ExunitCheck.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[options]
generate-tests = true

[[supervisors]]
name = "main"
strategy = "one_for_one"
max-restarts = 3
max-seconds = 5
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    let helper =
        std::fs::read_to_string(output_dir.join("test/test_helper.exs")).expect("read test_helper");
    assert!(
        helper.contains("ExUnit.start()"),
        "test_helper.exs must call ExUnit.start()"
    );

    let test =
        std::fs::read_to_string(output_dir.join("test/exunit_check_test.exs")).expect("read test");
    assert!(
        test.contains("use ExUnit.Case"),
        "Test module must use ExUnit.Case"
    );
    assert!(
        test.contains("ExunitCheck"),
        "Test module references the app"
    );
}

#[test]
fn test_generate_tests_false_skips_test_files() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "no_tests"
entry = "NoTests.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"

[options]
generate-tests = false
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    assert!(
        !output_dir.join("test").exists(),
        "test/ dir should not exist when generate-tests = false"
    );
}

#[test]
fn test_generated_files_have_spdx_headers() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "spdx_check"
entry = "SpdxCheck.Application"
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
name = "worker-a"
type = "worker"
restart = "permanent"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    // Note: without explicit [options] generate-tests = true, test files may not exist.
    // The manifest above does not include [options], so only check generated lib files.
    let files_to_check = vec![
        "mix.exs",
        ".formatter.exs",
        "lib/spdx_check/application.ex",
        "lib/spdx_check/main_supervisor.ex",
        "lib/spdx_check/worker_a.ex",
    ];
    for file in &files_to_check {
        let content = std::fs::read_to_string(output_dir.join(file))
            .unwrap_or_else(|_| panic!("Should read {}", file));
        assert!(
            content.contains("SPDX-License-Identifier: PMPL-1.0-or-later"),
            "File {} must have SPDX header",
            file
        );
    }
}

#[test]
fn test_module_name_edge_cases() {
    // Multiple consecutive delimiters.
    assert_eq!(manifest::to_module_name("a--b"), "AB");
    // Leading/trailing delimiters.
    assert_eq!(manifest::to_module_name("-leading"), "Leading");
    assert_eq!(manifest::to_module_name("trailing-"), "Trailing");
    // Mixed delimiters.
    assert_eq!(manifest::to_module_name("mix-ed_case"), "MixEdCase");
    // Single character.
    assert_eq!(manifest::to_module_name("x"), "X");
    // Empty string.
    assert_eq!(manifest::to_module_name(""), "");
}

#[test]
fn test_atom_name_edge_cases() {
    assert_eq!(manifest::to_atom_name("already_snake"), "already_snake");
    assert_eq!(manifest::to_atom_name("multi--dash"), "multi__dash");
    assert_eq!(manifest::to_atom_name("no-dash"), "no_dash");
}

#[test]
fn test_worker_module_with_explicit_module_name() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "mod_override"
entry = "ModOverride.Application"
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
name = "my-cache"
type = "worker"
module = "Redis.CacheAdapter"
restart = "permanent"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let m = manifest::load_manifest(&manifest_path).expect("Should parse");
    let output_dir = tmp.path().join("output");
    otpiser::codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("codegen");

    // Worker file uses the atom name of the child name, not the module override.
    assert!(output_dir.join("lib/mod_override/my_cache.ex").exists());
    let worker = std::fs::read_to_string(output_dir.join("lib/mod_override/my_cache.ex"))
        .expect("read worker");
    // Module name should use the explicit module field.
    assert!(
        worker.contains("ModOverride.Redis.CacheAdapter"),
        "Worker must use explicit module name"
    );
}

// ===========================================================================
// ABI tests: ProcessTree methods and types
// ===========================================================================

use otpiser::abi::{
    ChildRestartType, ChildSpec, ChildType, ProcessTree, RestartIntensity, ShutdownType,
    SupervisorStrategy,
};

#[test]
fn test_process_tree_depth_single_worker() {
    let tree = ProcessTree::WorkerNode {
        spec: ChildSpec {
            child_id: "w1".to_string(),
            start_module: "W1".to_string(),
            start_args: vec![],
            restart_type: ChildRestartType::Permanent,
            shutdown: ShutdownType::Timeout(5000),
            child_type: ChildType::Worker,
        },
    };
    assert_eq!(tree.depth(), 0, "Single worker has depth 0");
}

#[test]
fn test_process_tree_depth_one_level() {
    let tree = ProcessTree::SupervisorNode {
        name: "root".to_string(),
        strategy: SupervisorStrategy::OneForOne,
        intensity: RestartIntensity::default(),
        children: vec![ProcessTree::WorkerNode {
            spec: ChildSpec {
                child_id: "w1".to_string(),
                start_module: "W1".to_string(),
                start_args: vec![],
                restart_type: ChildRestartType::Permanent,
                shutdown: ShutdownType::Timeout(5000),
                child_type: ChildType::Worker,
            },
        }],
    };
    assert_eq!(tree.depth(), 1, "Supervisor with worker child has depth 1");
}

#[test]
fn test_process_tree_depth_three_levels() {
    let tree = ProcessTree::SupervisorNode {
        name: "root".to_string(),
        strategy: SupervisorStrategy::OneForOne,
        intensity: RestartIntensity::default(),
        children: vec![ProcessTree::SupervisorNode {
            name: "mid".to_string(),
            strategy: SupervisorStrategy::OneForAll,
            intensity: RestartIntensity::default(),
            children: vec![ProcessTree::SupervisorNode {
                name: "deep".to_string(),
                strategy: SupervisorStrategy::RestForOne,
                intensity: RestartIntensity::default(),
                children: vec![ProcessTree::WorkerNode {
                    spec: ChildSpec {
                        child_id: "leaf".to_string(),
                        start_module: "Leaf".to_string(),
                        start_args: vec![],
                        restart_type: ChildRestartType::Transient,
                        shutdown: ShutdownType::Timeout(5000),
                        child_type: ChildType::Worker,
                    },
                }],
            }],
        }],
    };
    assert_eq!(tree.depth(), 3, "Three levels of supervisors gives depth 3");
}

#[test]
fn test_process_tree_worker_count_across_tree() {
    let tree = ProcessTree::SupervisorNode {
        name: "root".to_string(),
        strategy: SupervisorStrategy::OneForOne,
        intensity: RestartIntensity::default(),
        children: vec![
            ProcessTree::WorkerNode {
                spec: ChildSpec {
                    child_id: "w1".to_string(),
                    start_module: "W1".to_string(),
                    start_args: vec![],
                    restart_type: ChildRestartType::Permanent,
                    shutdown: ShutdownType::Timeout(5000),
                    child_type: ChildType::Worker,
                },
            },
            ProcessTree::SupervisorNode {
                name: "sub".to_string(),
                strategy: SupervisorStrategy::OneForAll,
                intensity: RestartIntensity::default(),
                children: vec![
                    ProcessTree::WorkerNode {
                        spec: ChildSpec {
                            child_id: "w2".to_string(),
                            start_module: "W2".to_string(),
                            start_args: vec![],
                            restart_type: ChildRestartType::Transient,
                            shutdown: ShutdownType::BrutalKill,
                            child_type: ChildType::Worker,
                        },
                    },
                    ProcessTree::WorkerNode {
                        spec: ChildSpec {
                            child_id: "w3".to_string(),
                            start_module: "W3".to_string(),
                            start_args: vec![],
                            restart_type: ChildRestartType::Temporary,
                            shutdown: ShutdownType::Infinity,
                            child_type: ChildType::Worker,
                        },
                    },
                ],
            },
        ],
    };
    assert_eq!(tree.worker_count(), 3, "Should count all 3 workers");
    assert_eq!(tree.size(), 5, "Total nodes: 2 supervisors + 3 workers = 5");
}

#[test]
fn test_process_tree_empty_supervisor() {
    let tree = ProcessTree::SupervisorNode {
        name: "empty".to_string(),
        strategy: SupervisorStrategy::OneForOne,
        intensity: RestartIntensity::default(),
        children: vec![],
    };
    assert_eq!(tree.depth(), 1, "Empty supervisor has depth 1");
    assert_eq!(tree.worker_count(), 0, "Empty supervisor has 0 workers");
    assert_eq!(tree.size(), 1, "Empty supervisor counts as 1 node");
}

#[test]
fn test_strategy_enum_values() {
    // Verify repr values match expected ABI constants.
    assert_eq!(SupervisorStrategy::OneForOne as u32, 0);
    assert_eq!(SupervisorStrategy::OneForAll as u32, 1);
    assert_eq!(SupervisorStrategy::RestForOne as u32, 2);
}

#[test]
fn test_child_restart_type_enum_values() {
    assert_eq!(ChildRestartType::Permanent as u32, 0);
    assert_eq!(ChildRestartType::Transient as u32, 1);
    assert_eq!(ChildRestartType::Temporary as u32, 2);
}

#[test]
fn test_child_type_enum_values() {
    assert_eq!(ChildType::Worker as u32, 0);
    assert_eq!(ChildType::Supervisor as u32, 1);
}

#[test]
fn test_restart_intensity_default() {
    let default = RestartIntensity::default();
    assert_eq!(default.max_restarts, 3, "Default max_restarts is 3");
    assert_eq!(default.max_seconds, 5, "Default max_seconds is 5");
}

#[test]
fn test_shutdown_type_variants() {
    let timeout = ShutdownType::Timeout(5000);
    let brutal = ShutdownType::BrutalKill;
    let infinity = ShutdownType::Infinity;

    assert_eq!(timeout, ShutdownType::Timeout(5000));
    assert_ne!(timeout, brutal);
    assert_ne!(brutal, infinity);
}

#[test]
fn test_convenience_generate_function() {
    let tmp = TempDir::new().expect("Failed to create temp dir");
    let manifest_toml = r#"
[workload]
name = "conv_test"
entry = "ConvTest.Application"
strategy = "one_for_one"

[data]
input-type = "In"
output-type = "Out"
"#;
    let manifest_path = write_manifest(&tmp, manifest_toml);
    let output_dir = tmp.path().join("output");

    // Use the top-level convenience function.
    otpiser::generate(&manifest_path, output_dir.to_str().unwrap())
        .expect("Convenience generate function should succeed");

    assert!(output_dir.join("mix.exs").exists());
    assert!(output_dir.join("lib/conv_test/application.ex").exists());
}
