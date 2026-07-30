use std::fs;
use std::io;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SshConfigOptions {
    pub handshake_host: String,
    pub handshake_user: String,
    pub identity_file: String,
    pub gitlab_local_port: u16,
}

impl Default for SshConfigOptions {
    fn default() -> Self {
        Self {
            handshake_host: "106.14.219.191".to_string(),
            handshake_user: "gitproxy".to_string(),
            identity_file: "~/.ssh/id_ed25519".to_string(),
            gitlab_local_port: 12222,
        }
    }
}

pub fn render_managed_config(options: &SshConfigOptions) -> String {
    format!(
        "Host handshake\n    HostName {}\n    User {}\n    IdentityFile {}\n    IdentitiesOnly yes\n\nHost gitlab-via-handshake\n    HostName 127.0.0.1\n    Port {}\n    User git\n    ProxyJump handshake\n",
        options.handshake_host,
        options.handshake_user,
        options.identity_file,
        options.gitlab_local_port
    )
}

pub fn write_managed_config(path: &Path, options: &SshConfigOptions) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, render_managed_config(options))
}

pub fn ensure_include(config_path: &Path, include_path: &Path) -> io::Result<()> {
    if let Some(parent) = config_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let include_line = format!("Include {}", include_path.display());
    let mut config = if config_path.exists() {
        fs::read_to_string(config_path)?
    } else {
        String::new()
    };

    if config.lines().any(|line| line.trim() == include_line) {
        return Ok(());
    }

    if !config.is_empty() && !config.ends_with('\n') {
        config.push('\n');
    }
    config.push_str(&include_line);
    config.push('\n');
    fs::write(config_path, config)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn tmp_path(name: &str) -> std::path::PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("handshake-client-{name}-{suffix}"))
    }

    #[test]
    fn renders_managed_ssh_config() {
        let output = render_managed_config(&SshConfigOptions {
            handshake_host: "106.14.219.191".to_string(),
            handshake_user: "gitproxy".to_string(),
            identity_file: "~/.ssh/id_ed25519".to_string(),
            gitlab_local_port: 12222,
        });

        assert!(output.contains("Host handshake"));
        assert!(output.contains("    HostName 106.14.219.191"));
        assert!(output.contains("    User gitproxy"));
        assert!(output.contains("    IdentityFile ~/.ssh/id_ed25519"));
        assert!(output.contains("Host gitlab-via-handshake"));
        assert!(output.contains("    Port 12222"));
        assert!(output.contains("    ProxyJump handshake"));
    }

    #[test]
    fn ensures_include_line_and_creates_parent_directory() {
        let config_path = tmp_path("ssh-config").join(".ssh/config");
        let include_path = tmp_path("include").join("handshake_config");

        ensure_include(&config_path, &include_path).unwrap();

        let output = fs::read_to_string(&config_path).unwrap();
        assert_eq!(output, format!("Include {}\n", include_path.display()));
    }

    #[test]
    fn does_not_duplicate_existing_include() {
        let config_path = tmp_path("ssh-config-duplicate");
        let include_path = tmp_path("include-duplicate");
        fs::write(
            &config_path,
            format!(
                "Host *\n    ServerAliveInterval 30\nInclude {}\n",
                include_path.display()
            ),
        )
        .unwrap();

        ensure_include(&config_path, &include_path).unwrap();

        let output = fs::read_to_string(&config_path).unwrap();
        assert_eq!(output.matches("Include ").count(), 1);
    }

    #[test]
    fn writes_managed_config_file() {
        let path = tmp_path("managed-config").join("handshake_config");
        let options = SshConfigOptions::default();

        write_managed_config(&path, &options).unwrap();

        assert!(
            fs::read_to_string(path)
                .unwrap()
                .contains("Host gitlab-via-handshake")
        );
    }
}
