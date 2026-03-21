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
}

/// Default supervision strategy.
fn default_strategy() -> String {
    "one_for_one".to_string()
}

/// Valid OTP supervision strategies.
const VALID_STRATEGIES: &[&str] = &["one_for_one", "one_for_all", "rest_for_one"];

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
    toml::from_str(&content)
        .with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate an otpiser manifest for correctness.
/// Checks required fields, valid strategies, and valid flags.
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
}
