use crate::BakugouError;
use std::path::Path;
use std::process::Stdio;
use std::time::Duration;
use tokio::process::Command;
use tokio::time::timeout;

/// Raw command output from a gh subprocess.
#[derive(Debug, Clone)]
pub struct CommandRunOutput {
    pub stdout: String,
}

/// Responsible for locating and executing the GitHub CLI.
#[derive(Debug, Clone)]
pub struct GhCommandRunner {
    executable: String,
}

impl Default for GhCommandRunner {
    fn default() -> Self {
        Self::new()
    }
}

impl GhCommandRunner {
    pub fn new() -> Self {
        Self {
            executable: resolve_gh_executable(),
        }
    }

    pub async fn run(
        &self,
        args: &[String],
        working_dir: Option<&Path>,
        timeout_secs: u64,
    ) -> Result<CommandRunOutput, BakugouError> {
        let command_repr = format!("{} {}", self.executable, args.join(" "));

        let mut cmd = Command::new(&self.executable);
        cmd.args(args);
        cmd.stdin(Stdio::null());
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());
        apply_non_interactive_env(&mut cmd);

        if let Some(dir) = working_dir {
            cmd.current_dir(dir);
        }

        let output = match timeout(Duration::from_secs(timeout_secs), cmd.output()).await {
            Err(_) => {
                return Err(BakugouError::Timeout {
                    command: command_repr,
                    timeout_secs,
                });
            }
            Ok(Err(err)) => {
                return if err.kind() == std::io::ErrorKind::NotFound {
                    Err(BakugouError::GhNotInstalled)
                } else {
                    Err(BakugouError::CommandFailed {
                        message: format!("failed to execute gh command: {err}"),
                        exit_code: None,
                        stderr: String::new(),
                        stdout: String::new(),
                    })
                };
            }
            Ok(Ok(output)) => output,
        };

        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let exit_code = output.status.code();

        if output.status.success() {
            return Ok(CommandRunOutput { stdout });
        }

        Err(classify_failed_command(exit_code, &stdout, &stderr))
    }
}

fn apply_non_interactive_env(cmd: &mut Command) {
    cmd.env("GH_PROMPT_DISABLED", "1");
    cmd.env("GH_PAGER", "cat");
    cmd.env("PAGER", "cat");
    cmd.env("NO_COLOR", "1");
    cmd.env("CLICOLOR", "0");
}

fn resolve_gh_executable() -> String {
    if let Ok(path) = std::env::var("GH_PATH") {
        let trimmed = path.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    for candidate in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] {
        if Path::new(candidate).exists() {
            return candidate.to_string();
        }
    }

    "gh".to_string()
}

fn classify_failed_command(exit_code: Option<i32>, stdout: &str, stderr: &str) -> BakugouError {
    let combined = format!("{stderr}\n{stdout}").to_ascii_lowercase();

    if combined.contains("not logged into")
        || combined.contains("authentication")
        || combined.contains("run `gh auth login`")
    {
        return BakugouError::GhNotAuthenticated {
            message: non_empty(stderr, stdout, "GitHub CLI is not authenticated"),
        };
    }

    if combined.contains("not a git repository")
        || combined.contains("no git remotes")
        || combined.contains("unable to find git repository")
        || combined.contains("could not determine base repository")
    {
        return BakugouError::InvalidRepository {
            message: non_empty(stderr, stdout, "invalid repository"),
        };
    }

    if combined.contains("pull request not found")
        || combined.contains("no pull requests found")
        || combined.contains("not found")
    {
        return BakugouError::NotFound {
            message: non_empty(stderr, stdout, "resource not found"),
        };
    }

    if combined.contains("unknown flag")
        || combined.contains("invalid value")
        || combined.contains("requires")
    {
        return BakugouError::InvalidParams {
            message: non_empty(stderr, stdout, "invalid parameters"),
        };
    }

    BakugouError::CommandFailed {
        message: non_empty(
            stderr,
            stdout,
            &format!("gh command failed with exit code {:?}", exit_code),
        ),
        exit_code,
        stderr: stderr.to_string(),
        stdout: stdout.to_string(),
    }
}

fn non_empty(primary: &str, secondary: &str, fallback: &str) -> String {
    if !primary.trim().is_empty() {
        primary.to_string()
    } else if !secondary.trim().is_empty() {
        secondary.to_string()
    } else {
        fallback.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_auth_error() {
        let err = classify_failed_command(Some(1), "", "not logged into any GitHub hosts");
        assert!(matches!(err, BakugouError::GhNotAuthenticated { .. }));
    }

    #[test]
    fn classify_repo_error() {
        let err = classify_failed_command(Some(1), "", "fatal: not a git repository");
        assert!(matches!(err, BakugouError::InvalidRepository { .. }));
    }

    #[test]
    fn classify_not_found_error() {
        let err = classify_failed_command(Some(1), "", "pull request not found");
        assert!(matches!(err, BakugouError::NotFound { .. }));
    }

    #[test]
    fn classify_invalid_params_error() {
        let err = classify_failed_command(Some(1), "", "unknown flag: --oops");
        assert!(matches!(err, BakugouError::InvalidParams { .. }));
    }

    #[test]
    fn classify_fallback_command_error() {
        let err = classify_failed_command(Some(1), "", "some other failure");
        assert!(matches!(err, BakugouError::CommandFailed { .. }));
    }

    #[test]
    fn picks_gh_path_env_when_set() {
        std::env::set_var("GH_PATH", "/custom/gh");
        let resolved = resolve_gh_executable();
        std::env::remove_var("GH_PATH");
        assert_eq!(resolved, "/custom/gh");
    }
}
