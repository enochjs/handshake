use std::error::Error;
use std::fmt::{Display, Formatter};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegisterKeyRequest<'a> {
    pub token: &'a str,
    pub public_key: &'a str,
    pub comment: &'a str,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct HttpCommandResult {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyRegisterError {
    message: String,
}

impl KeyRegisterError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for KeyRegisterError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for KeyRegisterError {}

pub trait HttpCommandRunner {
    fn run(&self, args: &[String]) -> Result<HttpCommandResult, KeyRegisterError>;
}

pub struct CurlCommandRunner;

impl HttpCommandRunner for CurlCommandRunner {
    fn run(&self, args: &[String]) -> Result<HttpCommandResult, KeyRegisterError> {
        let output = Command::new("curl")
            .args(args)
            .output()
            .map_err(|error| KeyRegisterError::new(format!("failed to run curl: {error}")))?;

        Ok(HttpCommandResult {
            status: output.status.code().unwrap_or(1),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        })
    }
}

pub struct CurlKeyRegistrar<R> {
    runner: R,
}

impl<R> CurlKeyRegistrar<R> {
    pub fn new(runner: R) -> Self {
        Self { runner }
    }

    pub fn runner(&self) -> &R {
        &self.runner
    }
}

impl<R: HttpCommandRunner> CurlKeyRegistrar<R> {
    pub fn register(
        &self,
        server_url: &str,
        request: &RegisterKeyRequest<'_>,
    ) -> Result<(), KeyRegisterError> {
        let endpoint = keys_endpoint(server_url);
        let body = register_key_json(request);
        let args = vec![
            "--fail".to_string(),
            "-sS".to_string(),
            "-X".to_string(),
            "POST".to_string(),
            "-H".to_string(),
            "Content-Type: application/json".to_string(),
            "-d".to_string(),
            body,
            endpoint,
        ];
        let result = self.runner.run(&args)?;

        if result.status != 0 {
            return Err(KeyRegisterError::new(error_message(
                &result.stderr,
                &result.stdout,
                "key registration failed",
            )));
        }

        Ok(())
    }
}

pub fn register_key_json(request: &RegisterKeyRequest<'_>) -> String {
    format!(
        "{{\"token\":\"{}\",\"public_key\":\"{}\",\"comment\":\"{}\"}}",
        json_escape(request.token),
        json_escape(request.public_key),
        json_escape(request.comment)
    )
}

fn keys_endpoint(server_url: &str) -> String {
    format!("{}/keys", server_url.trim_end_matches('/'))
}

fn json_escape(value: &str) -> String {
    let mut escaped = String::new();
    for character in value.chars() {
        match character {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            other => escaped.push(other),
        }
    }
    escaped
}

fn error_message(stderr: &str, stdout: &str, fallback: &str) -> String {
    let stderr = stderr.trim();
    if !stderr.is_empty() {
        return stderr.to_string();
    }
    let stdout = stdout.trim();
    if !stdout.is_empty() {
        return stdout.to_string();
    }
    fallback.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    #[derive(Default)]
    struct FakeRunner {
        calls: RefCell<Vec<Vec<String>>>,
        result: RefCell<HttpCommandResult>,
    }

    impl HttpCommandRunner for FakeRunner {
        fn run(&self, args: &[String]) -> Result<HttpCommandResult, KeyRegisterError> {
            self.calls.borrow_mut().push(args.to_vec());
            Ok(self.result.borrow().clone())
        }
    }

    #[test]
    fn escapes_json_strings() {
        let json = register_key_json(&RegisterKeyRequest {
            token: "tok\"en",
            public_key: "ssh-ed25519 AAAA user@example",
            comment: "line\nbreak",
        });

        assert_eq!(
            json,
            "{\"token\":\"tok\\\"en\",\"public_key\":\"ssh-ed25519 AAAA user@example\",\"comment\":\"line\\nbreak\"}"
        );
    }

    #[test]
    fn posts_public_key_to_keys_endpoint_with_curl() {
        let runner = FakeRunner {
            calls: RefCell::new(Vec::new()),
            result: RefCell::new(HttpCommandResult {
                status: 0,
                stdout: "{\"ok\":true}".to_string(),
                stderr: String::new(),
            }),
        };
        let registrar = CurlKeyRegistrar::new(runner);

        registrar
            .register(
                "http://example.test/root/",
                &RegisterKeyRequest {
                    token: "token",
                    public_key: "ssh-ed25519 AAAA user@example",
                    comment: "user@example",
                },
            )
            .unwrap();

        let calls = registrar.runner().calls.borrow();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0][0], "--fail");
        assert!(calls[0].contains(&"-sS".to_string()));
        assert!(calls[0].contains(&"http://example.test/root/keys".to_string()));
        assert!(calls[0].contains(&"Content-Type: application/json".to_string()));
        assert!(
            calls[0]
                .iter()
                .any(|arg| arg.contains("\"token\":\"token\""))
        );
    }

    #[test]
    fn propagates_curl_failure() {
        let runner = FakeRunner {
            calls: RefCell::new(Vec::new()),
            result: RefCell::new(HttpCommandResult {
                status: 22,
                stdout: String::new(),
                stderr: "forbidden".to_string(),
            }),
        };
        let registrar = CurlKeyRegistrar::new(runner);

        let error = registrar
            .register(
                "http://example.test",
                &RegisterKeyRequest {
                    token: "bad",
                    public_key: "ssh-ed25519 AAAA user@example",
                    comment: "",
                },
            )
            .unwrap_err();

        assert_eq!(error.to_string(), "forbidden");
    }
}
