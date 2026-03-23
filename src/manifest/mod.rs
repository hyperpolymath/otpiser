// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for otpiser.toml.
// Parses OTP supervision tree descriptions from TOML into Rust types.
// The manifest captures service architecture, supervision strategies,
// restart intensity, and child spec definitions.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Top-level otpiser manifest.
/// Describes a service architecture that will be transformed into
/// an OTP supervision tree with GenServers and fault-tolerance scaffolding.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// The top-level workload (OTP application).
    pub workload: WorkloadConfig,
    /// Data types flowing through the service pipeline.
    pub data: DataConfig,
    /// OTP-specific generation options.
    #[serde(default)]
    pub options: Options,
    /// Supervisor definitions (if empty, a default root supervisor is generated).
    #[serde(default)]
    pub supervisors: Vec<SupervisorDef>,
}

/// Workload description — maps to an OTP Application.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkloadConfig {
    /// Application name (e.g., "payment_gateway").
    pub name: String,
    /// Entry module (e.g., "PaymentGateway.Application").
    pub entry: String,
    /// Root supervisor strategy: "one_for_one", "one_for_all", "rest_for_one".
    /// Defaults to "one_for_one" if not specified.
    #[serde(default = "default_strategy")]
    pub strategy: String,
}

/// Data types flowing through the pipeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataConfig {
    /// Input type for the service (e.g., "PaymentRequest").
    #[serde(rename = "input-type")]
    pub input_type: String,
    /// Output type for the service (e.g., "PaymentResult").
    #[serde(rename = "output-type")]
    pub output_type: String,
}

/// OTP-specific generation options.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Options {
    /// Feature flags: "distributed", "health-checks", "telemetry", "broadway".
    #[serde(default)]
    pub flags: Vec<String>,
    /// Whether to generate ExUnit test files.
    #[serde(default = "default_true", rename = "generate-tests")]
    pub generate_tests: bool,
    /// Whether to generate a Containerfile (Podman/Docker).
    #[serde(default, rename = "generate-docker")]
    pub generate_docker: bool,
}

/// Return true by default (for generate-tests).
fn default_true() -> bool {
    true
}

/// A supervisor definition in the manifest.
/// Each `[[supervisors]]` block defines one supervisor in the tree.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SupervisorDef {
    /// Name of this supervisor (used to derive module name).
    pub name: String,
    /// Supervision strategy: "one_for_one", "one_for_all", "rest_for_one".
    #[serde(default = "default_strategy")]
    pub strategy: String,
    /// Maximum restarts before the supervisor itself gives up.
    #[serde(default = "default_max_restarts", rename = "max-restarts")]
    pub max_restarts: u32,
    /// Time window in seconds for max-restarts.
    #[serde(default = "default_max_seconds", rename = "max-seconds")]
    pub max_seconds: u32,
    /// Children managed by this supervisor.
    #[serde(default)]
    pub children: Vec<ChildDef>,
}

/// A child definition within a supervisor.
/// Can be either a worker (GenServer) or a nested supervisor.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChildDef {
    /// Unique name for this child process.
    pub name: String,
    /// Type: "worker" or "supervisor".
    #[serde(default = "default_child_type", rename = "type")]
    pub child_type: String,
    /// Elixir module name. If omitted, derived from name.
    #[serde(default)]
    pub module: Option<String>,
    /// Restart type: "permanent", "transient", "temporary".
    #[serde(default = "default_restart")]
    pub restart: String,
    /// For child type "supervisor": the supervision strategy.
    #[serde(default)]
    pub strategy: Option<String>,
}

/// Default supervision strategy.
fn default_strategy() -> String {
    "one_for_one".to_string()
}

/// Default max restarts (OTP standard: 3).
fn default_max_restarts() -> u32 {
    3
}

/// Default max seconds (OTP standard: 5).
fn default_max_seconds() -> u32 {
    5
}

/// Default child type is "worker".
fn default_child_type() -> String {
    "worker".to_string()
}

/// Default restart type is "permanent".
fn default_restart() -> String {
    "permanent".to_string()
}

/// Valid OTP supervision strategies.
const VALID_STRATEGIES: &[&str] = &["one_for_one", "one_for_all", "rest_for_one"];

/// Valid child types.
const VALID_CHILD_TYPES: &[&str] = &["worker", "supervisor"];

/// Valid restart types.
const VALID_RESTART_TYPES: &[&str] = &["permanent", "transient", "temporary"];

/// Valid feature flags for the options section.
const VALID_FLAGS: &[&str] = &[
    "distributed",
    "health-checks",
    "telemetry",
    "broadway",
    "dynamic-supervisor",
    "registry",
    "task-supervisor",
];

/// Load and parse an otpiser.toml manifest from disk.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate an otpiser manifest for correctness.
/// Checks required fields, valid strategies, valid flags, and supervisor tree consistency.
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.workload.name.is_empty() {
        anyhow::bail!("workload.name is required");
    }
    if manifest.workload.entry.is_empty() {
        anyhow::bail!("workload.entry is required");
    }
    if !VALID_STRATEGIES.contains(&manifest.workload.strategy.as_str()) {
        anyhow::bail!(
            "Invalid supervision strategy '{}'. Must be one of: {}",
            manifest.workload.strategy,
            VALID_STRATEGIES.join(", ")
        );
    }
    for flag in &manifest.options.flags {
        if !VALID_FLAGS.contains(&flag.as_str()) {
            anyhow::bail!(
                "Unknown option flag '{}'. Valid flags: {}",
                flag,
                VALID_FLAGS.join(", ")
            );
        }
    }
    // Validate supervisor definitions.
    for sup in &manifest.supervisors {
        validate_supervisor(sup)?;
    }
    Ok(())
}

/// Validate a single supervisor definition and its children recursively.
fn validate_supervisor(sup: &SupervisorDef) -> Result<()> {
    if sup.name.is_empty() {
        anyhow::bail!("Supervisor name is required");
    }
    if !VALID_STRATEGIES.contains(&sup.strategy.as_str()) {
        anyhow::bail!(
            "Invalid strategy '{}' for supervisor '{}'. Must be one of: {}",
            sup.strategy,
            sup.name,
            VALID_STRATEGIES.join(", ")
        );
    }
    if sup.max_seconds == 0 {
        anyhow::bail!("max-seconds must be > 0 for supervisor '{}'", sup.name);
    }
    for child in &sup.children {
        validate_child(child)?;
    }
    Ok(())
}

/// Validate a child definition.
fn validate_child(child: &ChildDef) -> Result<()> {
    if child.name.is_empty() {
        anyhow::bail!("Child name is required");
    }
    if !VALID_CHILD_TYPES.contains(&child.child_type.as_str()) {
        anyhow::bail!(
            "Invalid child type '{}' for child '{}'. Must be one of: {}",
            child.child_type,
            child.name,
            VALID_CHILD_TYPES.join(", ")
        );
    }
    if !VALID_RESTART_TYPES.contains(&child.restart.as_str()) {
        anyhow::bail!(
            "Invalid restart type '{}' for child '{}'. Must be one of: {}",
            child.restart,
            child.name,
            VALID_RESTART_TYPES.join(", ")
        );
    }
    if child.child_type == "supervisor"
        && let Some(ref strat) = child.strategy
        && !VALID_STRATEGIES.contains(&strat.as_str())
    {
        anyhow::bail!(
            "Invalid strategy '{}' for child supervisor '{}'. Must be one of: {}",
            strat,
            child.name,
            VALID_STRATEGIES.join(", ")
        );
    }
    Ok(())
}

/// Initialise a new otpiser.toml manifest in the given directory.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("otpiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("otpiser.toml already exists");
    }
    let template = r#"# otpiser manifest — OTP supervision tree description
# See: https://github.com/hyperpolymath/otpiser

[workload]
name = "my_app"
entry = "MyApp.Application"
strategy = "one_for_one"  # one_for_one | one_for_all | rest_for_one

[data]
input-type = "Request"
output-type = "Response"

[options]
# Feature flags: distributed, health-checks, telemetry, broadway,
#                dynamic-supervisor, registry, task-supervisor
flags = ["health-checks"]
generate-tests = true
generate-docker = false

# Supervisor tree definition.
# Each [[supervisors]] block defines a supervisor.
# Children can be workers (GenServers) or nested supervisors.

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
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print human-readable information about a manifest.
pub fn print_info(manifest: &Manifest) {
    println!("=== OTPiser: {} ===", manifest.workload.name);
    println!("Entry:    {}", manifest.workload.entry);
    println!("Strategy: {}", manifest.workload.strategy);
    println!("Input:    {}", manifest.data.input_type);
    println!("Output:   {}", manifest.data.output_type);
    if !manifest.options.flags.is_empty() {
        println!("Flags:    {}", manifest.options.flags.join(", "));
    }
    if !manifest.supervisors.is_empty() {
        println!("\nSupervision Tree:");
        for sup in &manifest.supervisors {
            print_supervisor_info(sup, 1);
        }
    }
}

/// Print supervisor info with indentation.
fn print_supervisor_info(sup: &SupervisorDef, indent: usize) {
    let pad = "  ".repeat(indent);
    println!(
        "{}{} (strategy: {}, restarts: {}/{}s)",
        pad, sup.name, sup.strategy, sup.max_restarts, sup.max_seconds
    );
    for child in &sup.children {
        let child_pad = "  ".repeat(indent + 1);
        let module_str = child.module.as_deref().unwrap_or(&child.name);
        println!(
            "{}{} [{}] module={} restart={}",
            child_pad, child.name, child.child_type, module_str, child.restart
        );
    }
}

/// Derive an Elixir module name from a kebab-case or snake_case name.
/// e.g., "worker-pool" -> "WorkerPool", "cache" -> "Cache"
pub fn to_module_name(name: &str) -> String {
    name.split(['-', '_'])
        .filter(|s| !s.is_empty())
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                None => String::new(),
                Some(first) => {
                    let upper: String = first.to_uppercase().collect();
                    upper + chars.as_str()
                }
            }
        })
        .collect()
}

/// Derive an Elixir atom from a name (kebab-case to snake_case).
/// e.g., "worker-pool" -> "worker_pool"
pub fn to_atom_name(name: &str) -> String {
    name.replace('-', "_")
}
