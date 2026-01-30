//! Output formatting for the CLI.

#![allow(dead_code)]

use clap::ValueEnum;
use serde::Serialize;

/// Output format.
#[derive(Debug, Clone, Copy, Default, ValueEnum)]
pub enum OutputFormat {
    #[default]
    Text,
    Json,
}

/// Print output in the specified format.
pub fn print<T: Serialize + std::fmt::Display>(value: &T, format: &OutputFormat) {
    match format {
        OutputFormat::Text => println!("{}", value),
        OutputFormat::Json => {
            if let Ok(json) = serde_json::to_string_pretty(value) {
                println!("{}", json);
            } else {
                println!("{}", value);
            }
        }
    }
}

/// Print a success message.
pub fn print_success(message: &str, format: &OutputFormat) {
    match format {
        OutputFormat::Text => println!("{}", message),
        OutputFormat::Json => {
            println!(r#"{{"status":"success","message":"{}"}}"#, message);
        }
    }
}

/// Print an error message.
pub fn print_error(message: &str, format: &OutputFormat) {
    match format {
        OutputFormat::Text => eprintln!("Error: {}", message),
        OutputFormat::Json => {
            eprintln!(r#"{{"status":"error","message":"{}"}}"#, message);
        }
    }
}

/// Print a table row.
pub fn print_row(label: &str, value: &str) {
    println!("  {:<16} {}", format!("{}:", label), value);
}

/// Print a divider line.
pub fn print_divider() {
    println!("{}", "-".repeat(50));
}

/// Print a heading.
pub fn print_heading(text: &str) {
    println!("\n{}", text);
    print_divider();
}
