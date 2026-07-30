use std::error::Error;
use std::fmt::{Display, Formatter};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandResult {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitConfigError {
    message: String,
}

impl GitConfigError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for GitConfigError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for GitConfigError {}

pub trait CommandRunner {
    fn run(&self, args: &[String]) -> Result<CommandResult, GitConfigError>;
}

pub trait GitConfig {
    fn get_all(&self, key: &str) -> Result<Vec<String>, GitConfigError>;
    fn set(&self, key: &str, value: &str) -> Result<(), GitConfigError>;
    fn unset_all(&self, key: &str, value: &str) -> Result<(), GitConfigError>;
}

pub struct RunnerGitConfig<R> {
    runner: R,
}

impl<R> RunnerGitConfig<R> {
    pub fn new(runner: R) -> Self {
        Self { runner }
    }

    pub fn runner(&self) -> &R {
        &self.runner
    }
}

impl<R: CommandRunner> RunnerGitConfig<R> {
    fn run_git(&self, args: &[&str]) -> Result<CommandResult, GitConfigError> {
        let owned_args = args
            .iter()
            .map(|arg| (*arg).to_string())
            .collect::<Vec<_>>();
        self.runner.run(&owned_args)
    }
}

impl<R: CommandRunner> GitConfig for RunnerGitConfig<R> {
    fn get_all(&self, key: &str) -> Result<Vec<String>, GitConfigError> {
        let result = self.run_git(&["config", "--global", "--get-all", key])?;

        if result.status == 1 && result.stdout.trim().is_empty() {
            return Ok(Vec::new());
        }

        if result.status != 0 {
            return Err(GitConfigError::new(error_message(
                result.stderr,
                format!("git config read failed for {key}"),
            )));
        }

        Ok(result
            .stdout
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(str::to_string)
            .collect())
    }

    fn set(&self, key: &str, value: &str) -> Result<(), GitConfigError> {
        let result = self.run_git(&["config", "--global", key, value])?;
        if result.status != 0 {
            return Err(GitConfigError::new(error_message(
                result.stderr,
                format!("git config set failed for {key}"),
            )));
        }
        Ok(())
    }

    fn unset_all(&self, key: &str, value: &str) -> Result<(), GitConfigError> {
        let result = self.run_git(&["config", "--global", "--unset-all", key, value])?;
        if result.status != 0 && result.status != 5 {
            return Err(GitConfigError::new(error_message(
                result.stderr,
                format!("git config unset failed for {key}"),
            )));
        }
        Ok(())
    }
}

fn error_message(stderr: String, fallback: String) -> String {
    let stderr = stderr.trim();
    if stderr.is_empty() {
        fallback
    } else {
        stderr.to_string()
    }
}

pub struct ProcessGitRunner;

impl CommandRunner for ProcessGitRunner {
    fn run(&self, args: &[String]) -> Result<CommandResult, GitConfigError> {
        let output = Command::new("git")
            .args(args)
            .output()
            .map_err(|error| GitConfigError::new(format!("failed to run git: {error}")))?;

        Ok(CommandResult {
            status: output.status.code().unwrap_or(1),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    #[derive(Default)]
    struct FakeRunner {
        calls: RefCell<Vec<Vec<String>>>,
        responses: RefCell<Vec<CommandResult>>,
    }

    impl FakeRunner {
        fn with_responses(responses: Vec<CommandResult>) -> Self {
            Self {
                calls: RefCell::new(Vec::new()),
                responses: RefCell::new(responses),
            }
        }
    }

    impl CommandRunner for FakeRunner {
        fn run(&self, args: &[String]) -> Result<CommandResult, GitConfigError> {
            self.calls.borrow_mut().push(args.to_vec());
            Ok(self.responses.borrow_mut().remove(0))
        }
    }

    #[test]
    fn reads_all_global_values_for_a_key() {
        let runner = FakeRunner::with_responses(vec![CommandResult {
            status: 0,
            stdout: "one\ntwo\n".to_string(),
            stderr: String::new(),
        }]);
        let adapter = RunnerGitConfig::new(runner);

        let values = adapter.get_all("url.example.insteadOf").unwrap();

        assert_eq!(values, vec!["one".to_string(), "two".to_string()]);
        assert_eq!(
            adapter.runner().calls.borrow().as_slice(),
            &[vec![
                "config".to_string(),
                "--global".to_string(),
                "--get-all".to_string(),
                "url.example.insteadOf".to_string(),
            ]]
        );
    }

    #[test]
    fn returns_empty_list_when_key_is_missing() {
        let runner = FakeRunner::with_responses(vec![CommandResult {
            status: 1,
            stdout: String::new(),
            stderr: String::new(),
        }]);
        let adapter = RunnerGitConfig::new(runner);

        assert_eq!(
            adapter.get_all("url.missing.insteadOf").unwrap(),
            Vec::<String>::new()
        );
    }

    #[test]
    fn sets_and_unsets_global_keys() {
        let runner = FakeRunner::with_responses(vec![
            CommandResult {
                status: 0,
                stdout: String::new(),
                stderr: String::new(),
            },
            CommandResult {
                status: 0,
                stdout: String::new(),
                stderr: String::new(),
            },
        ]);
        let adapter = RunnerGitConfig::new(runner);

        adapter
            .set("url.example.insteadOf", "ssh://example/")
            .unwrap();
        adapter
            .unset_all("url.example.insteadOf", "ssh://other/")
            .unwrap();

        assert_eq!(
            adapter.runner().calls.borrow().as_slice(),
            &[
                vec![
                    "config".to_string(),
                    "--global".to_string(),
                    "url.example.insteadOf".to_string(),
                    "ssh://example/".to_string(),
                ],
                vec![
                    "config".to_string(),
                    "--global".to_string(),
                    "--unset-all".to_string(),
                    "url.example.insteadOf".to_string(),
                    "ssh://other/".to_string(),
                ],
            ]
        );
    }

    #[test]
    fn ignores_missing_key_when_unsetting() {
        let runner = FakeRunner::with_responses(vec![CommandResult {
            status: 5,
            stdout: String::new(),
            stderr: String::new(),
        }]);
        let adapter = RunnerGitConfig::new(runner);

        adapter
            .unset_all("url.example.insteadOf", "ssh://other/")
            .unwrap();
    }
}
