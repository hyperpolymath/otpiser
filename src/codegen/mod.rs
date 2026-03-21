// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation for Elixir OTP applications from otpiser manifest.
// Generates complete Elixir project scaffolding including:
// - Application module with start/2 callback
// - Supervisor modules with child specs and strategies
// - GenServer worker templates with init/handle_call/handle_cast/handle_info
// - mix.exs project file
// - ExUnit test files
// - ASCII supervision tree diagram

mod elixir;
mod diagram;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all artifacts: Elixir OTP application from manifest.
/// Creates the full project structure under the output directory.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Generate mix.exs project file.
    let mix_content = elixir::generate_mix_exs(manifest);
    fs::write(out.join("mix.exs"), &mix_content)
        .context("Failed to write mix.exs")?;
    println!("  [gen] mix.exs");

    // Create lib/ directory structure.
    let app_name = crate::manifest::to_atom_name(&manifest.workload.name);
    let lib_dir = out.join("lib").join(&app_name);
    fs::create_dir_all(&lib_dir)
        .context("Failed to create lib directory")?;

    // Generate Application module.
    let app_content = elixir::generate_application_module(manifest);
    fs::write(lib_dir.join("application.ex"), &app_content)
        .context("Failed to write application.ex")?;
    println!("  [gen] lib/{}/application.ex", app_name);

    // Generate Supervisor modules and Worker modules from supervisor tree.
    if manifest.supervisors.is_empty() {
        // No explicit supervisors — generate a default root supervisor.
        let sup_content = elixir::generate_default_supervisor(manifest);
        fs::write(lib_dir.join("supervisor.ex"), &sup_content)
            .context("Failed to write supervisor.ex")?;
        println!("  [gen] lib/{}/supervisor.ex", app_name);
    } else {
        for sup in &manifest.supervisors {
            // Generate supervisor module.
            let sup_content = elixir::generate_supervisor_module(manifest, sup);
            let sup_filename = format!("{}_supervisor.ex", crate::manifest::to_atom_name(&sup.name));
            fs::write(lib_dir.join(&sup_filename), &sup_content)
                .context(format!("Failed to write {}", sup_filename))?;
            println!("  [gen] lib/{}/{}", app_name, sup_filename);

            // Generate worker modules for each worker child.
            for child in &sup.children {
                if child.child_type == "worker" {
                    let worker_content = elixir::generate_worker_module(manifest, child);
                    let worker_filename = format!("{}.ex", crate::manifest::to_atom_name(&child.name));
                    fs::write(lib_dir.join(&worker_filename), &worker_content)
                        .context(format!("Failed to write {}", worker_filename))?;
                    println!("  [gen] lib/{}/{}", app_name, worker_filename);
                }
            }
        }
    }

    // Generate test files if enabled.
    if manifest.options.generate_tests {
        let test_dir = out.join("test");
        fs::create_dir_all(&test_dir)
            .context("Failed to create test directory")?;

        let test_helper = elixir::generate_test_helper();
        fs::write(test_dir.join("test_helper.exs"), &test_helper)
            .context("Failed to write test_helper.exs")?;
        println!("  [gen] test/test_helper.exs");

        let test_content = elixir::generate_test_file(manifest);
        let test_filename = format!("{}_test.exs", app_name);
        fs::write(test_dir.join(&test_filename), &test_content)
            .context(format!("Failed to write {}", test_filename))?;
        println!("  [gen] test/{}", test_filename);
    }

    // Generate ASCII supervision tree diagram.
    let tree_diagram = diagram::generate_tree_diagram(manifest);
    fs::write(out.join("SUPERVISION_TREE.txt"), &tree_diagram)
        .context("Failed to write SUPERVISION_TREE.txt")?;
    println!("  [gen] SUPERVISION_TREE.txt");

    // Generate .formatter.exs for consistent formatting.
    let formatter = elixir::generate_formatter();
    fs::write(out.join(".formatter.exs"), &formatter)
        .context("Failed to write .formatter.exs")?;
    println!("  [gen] .formatter.exs");

    Ok(())
}

/// Build generated artifacts (invokes mix compile).
pub fn build(manifest: &Manifest, release: bool) -> Result<()> {
    let mode = if release { "release" } else { "debug" };
    println!(
        "Building otpiser workload: {} (mode: {})",
        manifest.workload.name, mode
    );
    println!("  Run 'mix compile' in the generated directory to compile the Elixir project.");
    Ok(())
}

/// Run the workload (invokes mix run or iex).
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!("Running otpiser workload: {}", manifest.workload.name);
    println!("  Run 'iex -S mix' in the generated directory to start the application.");
    Ok(())
}
