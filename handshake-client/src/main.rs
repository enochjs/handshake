use handshake_client::git_config::{GitConfigError, ProcessGitRunner, RunnerGitConfig};
use handshake_client::key_register::{CurlCommandRunner, CurlKeyRegistrar, RegisterKeyRequest};
use handshake_client::rewrite_rules::ClientMode;
use handshake_client::setup::{SetupEnvironment, SetupError, SetupOptions, run_setup};
use handshake_client::ssh_config::{SshConfigOptions, ensure_include, write_managed_config};
use handshake_client::toggle_service::ToggleService;
use std::error::Error;
use std::fmt::{Display, Formatter};
use std::fs;
use std::path::{Path, PathBuf};

const DEFAULT_KEY_SERVER_URL: &str = "http://106.14.219.191:8787";

#[derive(Debug, Clone, PartialEq, Eq)]
enum CliCommand {
    Help,
    Status,
    Enable,
    Disable,
    Setup(SetupOptions),
}

#[cfg(test)]
fn parse_command(args: &[String]) -> Result<CliCommand, String> {
    parse_command_with_defaults(args, &CliDefaults::from_env())
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CliDefaults {
    home_dir: PathBuf,
    server_url: String,
}

impl CliDefaults {
    fn from_env() -> Self {
        Self {
            home_dir: std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from(".")),
            server_url: std::env::var("HANDSHAKE_KEY_SERVER_URL")
                .unwrap_or_else(|_| DEFAULT_KEY_SERVER_URL.to_string()),
        }
    }
}

fn parse_command_with_defaults(
    args: &[String],
    defaults: &CliDefaults,
) -> Result<CliCommand, String> {
    match args.get(1).map(String::as_str) {
        None | Some("help" | "-h" | "--help") => Ok(CliCommand::Help),
        Some("status") => Ok(CliCommand::Status),
        Some("enable") => Ok(CliCommand::Enable),
        Some("disable") => Ok(CliCommand::Disable),
        Some("setup") => parse_setup_command(&args[2..], defaults).map(CliCommand::Setup),
        Some(command) => Err(format!("未知命令: {command}")),
    }
}

fn parse_setup_command(args: &[String], defaults: &CliDefaults) -> Result<SetupOptions, String> {
    let mut token = None;
    let mut server_url = defaults.server_url.clone();
    let mut public_key_path = defaults.home_dir.join(".ssh/id_ed25519.pub");
    let mut ssh_config_path = defaults.home_dir.join(".ssh/config");
    let mut include_path = defaults.home_dir.join(".ssh/handshake_config");
    let mut key_comment = "handshake-client".to_string();
    let mut ssh = SshConfigOptions::default();

    let mut index = 0;
    while index < args.len() {
        let option = args[index].as_str();
        let value = args
            .get(index + 1)
            .ok_or_else(|| format!("{option} requires a value"))?;
        match option {
            "--token" => token = Some(value.clone()),
            "--server-url" => server_url = value.clone(),
            "--key" => public_key_path = PathBuf::from(value),
            "--ssh-config" => ssh_config_path = PathBuf::from(value),
            "--include-path" => include_path = PathBuf::from(value),
            "--handshake-host" => ssh.handshake_host = value.clone(),
            "--handshake-user" => ssh.handshake_user = value.clone(),
            "--identity-file" => ssh.identity_file = value.clone(),
            "--gitlab-local-port" => {
                ssh.gitlab_local_port = value
                    .parse::<u16>()
                    .map_err(|_| "--gitlab-local-port must be a number".to_string())?;
            }
            "--comment" => key_comment = value.clone(),
            unknown => return Err(format!("unknown setup option: {unknown}")),
        }
        index += 2;
    }

    let token = token.ok_or_else(|| "setup requires --token <token>".to_string())?;
    Ok(SetupOptions {
        token,
        server_url,
        public_key_path,
        ssh_config_path,
        include_path,
        key_comment,
        ssh,
    })
}

fn usage(program: &str) -> String {
    format!(
        "Usage:\n  {program} setup --token <token>\n  {program} status\n  {program} enable\n  {program} disable\n  {program} help\n"
    )
}

fn mode_message(mode: ClientMode) -> &'static str {
    match mode {
        ClientMode::Handshake => "当前: Git 命令会通过 handshake 访问 216 GitLab",
        ClientMode::Direct => "当前: Git 命令会直连 10.10.0.216:2222",
        ClientMode::Mixed => "当前: 配置冲突，运行 enable 或 disable 可整理 rewrite 规则",
        ClientMode::Unconfigured => "当前: 未配置 rewrite，运行 enable 可开启 handshake",
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CliError {
    message: String,
}

impl CliError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for CliError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for CliError {}

impl From<GitConfigError> for CliError {
    fn from(error: GitConfigError) -> Self {
        Self::new(error.to_string())
    }
}

impl From<SetupError> for CliError {
    fn from(error: SetupError) -> Self {
        Self::new(error.to_string())
    }
}

trait CliApp {
    fn status(&mut self) -> Result<ClientMode, CliError>;
    fn enable(&mut self) -> Result<ClientMode, CliError>;
    fn disable(&mut self) -> Result<ClientMode, CliError>;
    fn setup(&mut self, options: SetupOptions) -> Result<ClientMode, CliError>;
}

struct RealCliApp {
    service: ToggleService<RunnerGitConfig<ProcessGitRunner>>,
}

impl RealCliApp {
    fn new() -> Self {
        Self {
            service: ToggleService::new(RunnerGitConfig::new(ProcessGitRunner)),
        }
    }
}

impl CliApp for RealCliApp {
    fn status(&mut self) -> Result<ClientMode, CliError> {
        Ok(self.service.status()?.mode)
    }

    fn enable(&mut self) -> Result<ClientMode, CliError> {
        Ok(self.service.enable()?.mode)
    }

    fn disable(&mut self) -> Result<ClientMode, CliError> {
        Ok(self.service.disable()?.mode)
    }

    fn setup(&mut self, options: SetupOptions) -> Result<ClientMode, CliError> {
        let mut environment = RealSetupEnvironment {
            service: &mut self.service,
        };
        Ok(run_setup(&mut environment, &options)?.mode)
    }
}

fn run_cli(app: &mut impl CliApp, args: &[String]) -> Result<String, CliError> {
    run_cli_with_defaults(app, args, &CliDefaults::from_env())
}

fn run_cli_with_defaults(
    app: &mut impl CliApp,
    args: &[String],
    defaults: &CliDefaults,
) -> Result<String, CliError> {
    let program = args
        .first()
        .map(String::as_str)
        .unwrap_or("handshake-client");
    match parse_command_with_defaults(args, defaults) {
        Ok(CliCommand::Help) => Ok(usage(program)),
        Ok(CliCommand::Status) => Ok(format!("{}\n", mode_message(app.status()?))),
        Ok(CliCommand::Enable) => Ok(format!("{}\n", mode_message(app.enable()?))),
        Ok(CliCommand::Disable) => Ok(format!("{}\n", mode_message(app.disable()?))),
        Ok(CliCommand::Setup(options)) => Ok(format!("{}\n", mode_message(app.setup(options)?))),
        Err(error) => Err(CliError::new(format!("{error}\n{}", usage(program)))),
    }
}

struct RealSetupEnvironment<'a> {
    service: &'a mut ToggleService<RunnerGitConfig<ProcessGitRunner>>,
}

impl SetupEnvironment for RealSetupEnvironment<'_> {
    fn read_public_key(&mut self, path: &Path) -> Result<String, SetupError> {
        fs::read_to_string(path).map_err(SetupError::from)
    }

    fn register_key(
        &mut self,
        server_url: &str,
        token: &str,
        public_key: &str,
        comment: &str,
    ) -> Result<(), SetupError> {
        let registrar = CurlKeyRegistrar::new(CurlCommandRunner);
        registrar
            .register(
                server_url,
                &RegisterKeyRequest {
                    token,
                    public_key,
                    comment,
                },
            )
            .map_err(|error| SetupError::new(error.to_string()))
    }

    fn write_managed_config(
        &mut self,
        path: &Path,
        options: &SshConfigOptions,
    ) -> Result<(), SetupError> {
        write_managed_config(path, options).map_err(SetupError::from)
    }

    fn ensure_include(
        &mut self,
        config_path: &Path,
        include_path: &Path,
    ) -> Result<(), SetupError> {
        ensure_include(config_path, include_path).map_err(SetupError::from)
    }

    fn enable_handshake(&mut self) -> Result<ClientMode, SetupError> {
        self.service
            .enable()
            .map(|status| status.mode)
            .map_err(|error| SetupError::new(error.to_string()))
    }
}

fn main() {
    let args = std::env::args().collect::<Vec<_>>();
    let mut app = RealCliApp::new();

    match run_cli(&mut app, &args) {
        Ok(output) => {
            print!("{output}");
        }
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod cli_tests {
    use super::*;

    fn args(items: &[&str]) -> Vec<String> {
        items.iter().map(|item| (*item).to_string()).collect()
    }

    #[test]
    fn parses_cli_commands() {
        assert_eq!(
            parse_command(&args(&["git-hs"])).unwrap(),
            CliCommand::Help
        );
        assert_eq!(
            parse_command(&args(&["git-hs", "status"])).unwrap(),
            CliCommand::Status
        );
        assert_eq!(
            parse_command(&args(&["git-hs", "enable"])).unwrap(),
            CliCommand::Enable
        );
        assert_eq!(
            parse_command(&args(&["git-hs", "disable"])).unwrap(),
            CliCommand::Disable
        );
    }

    #[test]
    fn rejects_unknown_command() {
        assert_eq!(
            parse_command(&args(&["git-hs", "wat"])).unwrap_err(),
            "未知命令: wat"
        );
    }

    #[test]
    fn renders_usage() {
        let output = usage("git-hs");

        assert!(output.contains("git-hs status"));
        assert!(output.contains("git-hs enable"));
        assert!(output.contains("git-hs disable"));
        assert!(output.contains("git-hs setup --token"));
    }

    #[test]
    fn renders_mode_messages() {
        assert!(mode_message(ClientMode::Handshake).contains("通过 handshake"));
        assert!(mode_message(ClientMode::Direct).contains("直连"));
        assert!(mode_message(ClientMode::Mixed).contains("配置冲突"));
        assert!(mode_message(ClientMode::Unconfigured).contains("未配置"));
    }

    struct FakeApp {
        calls: Vec<&'static str>,
        mode: ClientMode,
        setup_options: Option<SetupOptions>,
    }

    impl Default for FakeApp {
        fn default() -> Self {
            Self {
                calls: Vec::new(),
                mode: ClientMode::Unconfigured,
                setup_options: None,
            }
        }
    }

    impl CliApp for FakeApp {
        fn status(&mut self) -> Result<ClientMode, CliError> {
            self.calls.push("status");
            Ok(self.mode)
        }

        fn enable(&mut self) -> Result<ClientMode, CliError> {
            self.calls.push("enable");
            Ok(ClientMode::Handshake)
        }

        fn disable(&mut self) -> Result<ClientMode, CliError> {
            self.calls.push("disable");
            Ok(ClientMode::Direct)
        }

        fn setup(&mut self, options: SetupOptions) -> Result<ClientMode, CliError> {
            self.calls.push("setup");
            self.setup_options = Some(options);
            Ok(ClientMode::Handshake)
        }
    }

    #[test]
    fn dispatches_status_command() {
        let mut app = FakeApp {
            calls: Vec::new(),
            mode: ClientMode::Direct,
            setup_options: None,
        };

        let output = run_cli(&mut app, &args(&["git-hs", "status"])).unwrap();

        assert_eq!(app.calls, vec!["status"]);
        assert!(output.contains("直连"));
    }

    #[test]
    fn dispatches_enable_and_disable_commands() {
        let mut app = FakeApp::default();

        let enabled = run_cli(&mut app, &args(&["git-hs", "enable"])).unwrap();
        let disabled = run_cli(&mut app, &args(&["git-hs", "disable"])).unwrap();

        assert_eq!(app.calls, vec!["enable", "disable"]);
        assert!(enabled.contains("通过 handshake"));
        assert!(disabled.contains("直连"));
    }

    #[test]
    fn parses_setup_command_with_defaults() {
        let command = parse_command_with_defaults(
            &args(&["git-hs", "setup", "--token", "invite-token"]),
            &CliDefaults {
                home_dir: std::path::PathBuf::from("/home/alice"),
                server_url: "http://server.test".to_string(),
            },
        )
        .unwrap();

        let CliCommand::Setup(options) = command else {
            panic!("expected setup command");
        };
        assert_eq!(options.token, "invite-token");
        assert_eq!(options.server_url, "http://server.test");
        assert_eq!(
            options.public_key_path,
            std::path::PathBuf::from("/home/alice/.ssh/id_ed25519.pub")
        );
        assert_eq!(
            options.ssh_config_path,
            std::path::PathBuf::from("/home/alice/.ssh/config")
        );
        assert_eq!(
            options.include_path,
            std::path::PathBuf::from("/home/alice/.ssh/handshake_config")
        );
        assert_eq!(options.ssh.handshake_user, "gitproxy");
    }

    #[test]
    fn rejects_setup_without_token() {
        let error = parse_command_with_defaults(
            &args(&["git-hs", "setup"]),
            &CliDefaults {
                home_dir: std::path::PathBuf::from("/home/alice"),
                server_url: "http://server.test".to_string(),
            },
        )
        .unwrap_err();

        assert_eq!(error, "setup requires --token <token>");
    }

    #[test]
    fn dispatches_setup_command() {
        let mut app = FakeApp::default();

        let output = run_cli_with_defaults(
            &mut app,
            &args(&["git-hs", "setup", "--token", "invite-token"]),
            &CliDefaults {
                home_dir: std::path::PathBuf::from("/home/alice"),
                server_url: "http://server.test".to_string(),
            },
        )
        .unwrap();

        assert_eq!(app.calls, vec!["setup"]);
        assert!(output.contains("通过 handshake"));
        assert_eq!(app.setup_options.unwrap().token, "invite-token");
    }
}
