use crate::git_config::{GitConfig, GitConfigError};
use crate::rewrite_rules::{
    ClientMode, DIRECT_PREFIX, DIRECT_REWRITE_KEY, HANDSHAKE_PREFIX, HANDSHAKE_REWRITE_KEY,
    RewriteValues, detect_mode,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToggleStatus {
    pub mode: ClientMode,
    pub direct_prefix: &'static str,
    pub handshake_prefix: &'static str,
}

pub struct ToggleService<G> {
    git_config: G,
}

impl<G> ToggleService<G> {
    pub fn new(git_config: G) -> Self {
        Self { git_config }
    }

    pub fn git_config(&self) -> &G {
        &self.git_config
    }
}

impl<G: GitConfig> ToggleService<G> {
    pub fn status(&self) -> Result<ToggleStatus, GitConfigError> {
        let direct_instead_of = self.git_config.get_all(HANDSHAKE_REWRITE_KEY)?;
        let handshake_instead_of = self.git_config.get_all(DIRECT_REWRITE_KEY)?;
        let direct_refs = direct_instead_of
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>();
        let handshake_refs = handshake_instead_of
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>();

        Ok(ToggleStatus {
            mode: detect_mode(RewriteValues {
                direct_instead_of: &direct_refs,
                handshake_instead_of: &handshake_refs,
            }),
            direct_prefix: DIRECT_PREFIX,
            handshake_prefix: HANDSHAKE_PREFIX,
        })
    }

    pub fn enable(&self) -> Result<ToggleStatus, GitConfigError> {
        self.git_config.set(HANDSHAKE_REWRITE_KEY, DIRECT_PREFIX)?;
        self.git_config
            .unset_all(DIRECT_REWRITE_KEY, HANDSHAKE_PREFIX)?;
        self.status()
    }

    pub fn disable(&self) -> Result<ToggleStatus, GitConfigError> {
        self.git_config.set(DIRECT_REWRITE_KEY, HANDSHAKE_PREFIX)?;
        self.git_config
            .unset_all(HANDSHAKE_REWRITE_KEY, DIRECT_PREFIX)?;
        self.status()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;

    #[derive(Default)]
    struct FakeGitConfig {
        store: RefCell<HashMap<String, Vec<String>>>,
        calls: RefCell<Vec<Vec<String>>>,
    }

    impl FakeGitConfig {
        fn with_values(values: &[(&str, &[&str])]) -> Self {
            let store = values
                .iter()
                .map(|(key, items)| {
                    (
                        (*key).to_string(),
                        items.iter().map(|item| (*item).to_string()).collect(),
                    )
                })
                .collect();

            Self {
                store: RefCell::new(store),
                calls: RefCell::new(Vec::new()),
            }
        }
    }

    impl GitConfig for FakeGitConfig {
        fn get_all(&self, key: &str) -> Result<Vec<String>, GitConfigError> {
            self.calls
                .borrow_mut()
                .push(vec!["get_all".to_string(), key.to_string()]);
            Ok(self.store.borrow().get(key).cloned().unwrap_or_default())
        }

        fn set(&self, key: &str, value: &str) -> Result<(), GitConfigError> {
            self.calls.borrow_mut().push(vec![
                "set".to_string(),
                key.to_string(),
                value.to_string(),
            ]);
            self.store
                .borrow_mut()
                .insert(key.to_string(), vec![value.to_string()]);
            Ok(())
        }

        fn unset_all(&self, key: &str, value: &str) -> Result<(), GitConfigError> {
            self.calls.borrow_mut().push(vec![
                "unset_all".to_string(),
                key.to_string(),
                value.to_string(),
            ]);
            self.store
                .borrow_mut()
                .entry(key.to_string())
                .and_modify(|items| items.retain(|item| item != value));
            Ok(())
        }
    }

    #[test]
    fn enables_handshake_mode_and_removes_direct_rewrite() {
        let git_config = FakeGitConfig::with_values(&[(
            "url.ssh://git@10.10.0.216:2222/.insteadOf",
            &["ssh://git@gitlab-via-handshake/"],
        )]);
        let service = ToggleService::new(git_config);

        service.enable().unwrap();

        assert!(service.git_config().calls.borrow().contains(&vec![
            "set".to_string(),
            "url.ssh://git@gitlab-via-handshake/.insteadOf".to_string(),
            "ssh://git@10.10.0.216:2222/".to_string(),
        ]));
        assert!(service.git_config().calls.borrow().contains(&vec![
            "unset_all".to_string(),
            "url.ssh://git@10.10.0.216:2222/.insteadOf".to_string(),
            "ssh://git@gitlab-via-handshake/".to_string(),
        ]));
    }

    #[test]
    fn disables_handshake_mode_and_removes_handshake_rewrite() {
        let git_config = FakeGitConfig::with_values(&[(
            "url.ssh://git@gitlab-via-handshake/.insteadOf",
            &["ssh://git@10.10.0.216:2222/"],
        )]);
        let service = ToggleService::new(git_config);

        service.disable().unwrap();

        assert!(service.git_config().calls.borrow().contains(&vec![
            "set".to_string(),
            "url.ssh://git@10.10.0.216:2222/.insteadOf".to_string(),
            "ssh://git@gitlab-via-handshake/".to_string(),
        ]));
        assert!(service.git_config().calls.borrow().contains(&vec![
            "unset_all".to_string(),
            "url.ssh://git@gitlab-via-handshake/.insteadOf".to_string(),
            "ssh://git@10.10.0.216:2222/".to_string(),
        ]));
    }

    #[test]
    fn reports_current_status() {
        let git_config = FakeGitConfig::with_values(&[(
            "url.ssh://git@gitlab-via-handshake/.insteadOf",
            &["ssh://git@10.10.0.216:2222/"],
        )]);
        let service = ToggleService::new(git_config);

        let status = service.status().unwrap();

        assert_eq!(status.mode, ClientMode::Handshake);
        assert_eq!(status.direct_prefix, "ssh://git@10.10.0.216:2222/");
        assert_eq!(status.handshake_prefix, "ssh://git@gitlab-via-handshake/");
    }
}
