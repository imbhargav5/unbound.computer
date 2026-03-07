//! Startup status tracking for daemon boot diagnostics.

use chrono::Utc;
use serde::Serialize;
use std::path::PathBuf;

#[derive(Clone)]
pub struct StartupStatusWriter {
    path: PathBuf,
}

#[derive(Serialize)]
struct StartupStatusRecord<'a> {
    phase: &'a str,
    detail: &'a str,
    updated_at: String,
}

impl StartupStatusWriter {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    pub fn clear(&self) {
        let _ = std::fs::remove_file(&self.path);
    }

    pub fn update(&self, phase: &str, detail: &str) {
        if let Some(parent) = self.path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        let record = StartupStatusRecord {
            phase,
            detail,
            updated_at: Utc::now().to_rfc3339(),
        };

        if let Ok(json) = serde_json::to_vec_pretty(&record) {
            let _ = std::fs::write(&self.path, json);
        }
    }
}
