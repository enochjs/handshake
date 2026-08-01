use crate::rewrite_rules::ClientMode;
use crate::ssh_config::SshConfigOptions;
use std::error::Error;
use std::fmt::{Display, Formatter};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupOptions {
    pub token: String,
    pub server_url: String,
    pub public_key_path: PathBuf,
    pub ssh_config_path: PathBuf,
    pub include_path: PathBuf,
    pub key_comment: String,
    pub ssh: SshConfigOptions,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupOutcome {
    pub mode: ClientMode,
    pub warnings: Vec<String>,
}

pub const REGISTRATION_FORBIDDEN_WARNING: &str = "邀请 token 校验失败（403），请联系 枫荷 处理。";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupError {
    message: String,
}

impl SetupError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for SetupError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for SetupError {}

impl From<std::io::Error> for SetupError {
    fn from(error: std::io::Error) -> Self {
        Self::new(error.to_string())
    }
}

pub trait SetupEnvironment {
    fn read_public_key(&mut self, path: &Path) -> Result<String, SetupError>;
    fn register_key(
        &mut self,
        server_url: &str,
        token: &str,
        public_key: &str,
        comment: &str,
    ) -> Result<(), SetupError>;
    fn write_managed_config(
        &mut self,
        path: &Path,
        options: &SshConfigOptions,
    ) -> Result<(), SetupError>;
    fn ensure_include(&mut self, config_path: &Path, include_path: &Path)
    -> Result<(), SetupError>;
    fn enable_handshake(&mut self) -> Result<ClientMode, SetupError>;
}

pub fn run_setup(
    environment: &mut impl SetupEnvironment,
    options: &SetupOptions,
) -> Result<SetupOutcome, SetupError> {
    let public_key = environment.read_public_key(&options.public_key_path)?;
    let mut warnings = Vec::new();
    match environment.register_key(
        &options.server_url,
        &options.token,
        public_key.trim(),
        &options.key_comment,
    ) {
        Ok(()) => {}
        Err(error) if error.to_string().contains("403") => {
            warnings.push(REGISTRATION_FORBIDDEN_WARNING.to_string());
        }
        Err(error) => return Err(error),
    }
    environment.write_managed_config(&options.include_path, &options.ssh)?;
    environment.ensure_include(&options.ssh_config_path, &options.include_path)?;
    Ok(SetupOutcome {
        mode: environment.enable_handshake()?,
        warnings,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rewrite_rules::ClientMode;
    use crate::ssh_config::SshConfigOptions;
    use std::path::{Path, PathBuf};

    #[derive(Default)]
    struct FakeEnvironment {
        calls: Vec<String>,
        register_error: Option<SetupError>,
    }

    impl SetupEnvironment for FakeEnvironment {
        fn read_public_key(&mut self, path: &Path) -> Result<String, SetupError> {
            self.calls.push(format!("read:{}", path.display()));
            Ok("ssh-ed25519 AAAA user@example".to_string())
        }

        fn register_key(
            &mut self,
            server_url: &str,
            token: &str,
            public_key: &str,
            comment: &str,
        ) -> Result<(), SetupError> {
            self.calls.push(format!(
                "register:{server_url}:{token}:{public_key}:{comment}"
            ));
            match &self.register_error {
                Some(error) => Err(error.clone()),
                None => Ok(()),
            }
        }

        fn write_managed_config(
            &mut self,
            path: &Path,
            options: &SshConfigOptions,
        ) -> Result<(), SetupError> {
            self.calls.push(format!(
                "write:{}:{}:{}",
                path.display(),
                options.handshake_host,
                options.handshake_user
            ));
            Ok(())
        }

        fn ensure_include(
            &mut self,
            config_path: &Path,
            include_path: &Path,
        ) -> Result<(), SetupError> {
            self.calls.push(format!(
                "include:{}:{}",
                config_path.display(),
                include_path.display()
            ));
            Ok(())
        }

        fn enable_handshake(&mut self) -> Result<ClientMode, SetupError> {
            self.calls.push("enable".to_string());
            Ok(ClientMode::Handshake)
        }
    }

    #[test]
    fn setup_runs_registration_config_and_enable_in_order() {
        let mut environment = FakeEnvironment::default();
        let options = SetupOptions {
            token: "token-1".to_string(),
            server_url: "http://server.test".to_string(),
            public_key_path: PathBuf::from("/tmp/id.pub"),
            ssh_config_path: PathBuf::from("/tmp/ssh_config"),
            include_path: PathBuf::from("/tmp/handshake_config"),
            key_comment: "teammate@example".to_string(),
            ssh: SshConfigOptions {
                handshake_host: "106.14.219.191".to_string(),
                handshake_user: "gitproxy".to_string(),
                identity_file: "~/.ssh/id_ed25519".to_string(),
                gitlab_local_port: 12222,
            },
        };

        let outcome = run_setup(&mut environment, &options).unwrap();

        assert_eq!(outcome.mode, ClientMode::Handshake);
        assert_eq!(outcome.warnings, Vec::<String>::new());
        assert_eq!(
            environment.calls,
            vec![
                "read:/tmp/id.pub",
                "register:http://server.test:token-1:ssh-ed25519 AAAA user@example:teammate@example",
                "write:/tmp/handshake_config:106.14.219.191:gitproxy",
                "include:/tmp/ssh_config:/tmp/handshake_config",
                "enable",
            ]
        );
    }

    #[test]
    fn setup_continues_with_warning_when_registration_returns_403() {
        let mut environment = FakeEnvironment {
            calls: Vec::new(),
            register_error: Some(SetupError::new(
                "curl: (22) The requested URL returned error: 403",
            )),
        };
        let options = SetupOptions {
            token: "expired-token".to_string(),
            server_url: "http://server.test".to_string(),
            public_key_path: PathBuf::from("/tmp/id.pub"),
            ssh_config_path: PathBuf::from("/tmp/ssh_config"),
            include_path: PathBuf::from("/tmp/handshake_config"),
            key_comment: "teammate@example".to_string(),
            ssh: SshConfigOptions::default(),
        };

        let outcome = run_setup(&mut environment, &options).unwrap();

        assert_eq!(outcome.mode, ClientMode::Handshake);
        assert_eq!(
            outcome.warnings,
            vec![REGISTRATION_FORBIDDEN_WARNING.to_string()]
        );
        assert_eq!(
            environment.calls,
            vec![
                "read:/tmp/id.pub",
                "register:http://server.test:expired-token:ssh-ed25519 AAAA user@example:teammate@example",
                "write:/tmp/handshake_config:106.14.219.191:gitproxy",
                "include:/tmp/ssh_config:/tmp/handshake_config",
                "enable",
            ]
        );
    }
}
