pub const DIRECT_PREFIX: &str = "ssh://git@10.10.0.216:2222/";
pub const HANDSHAKE_PREFIX: &str = "ssh://git@gitlab-via-handshake/";

pub const DIRECT_REWRITE_KEY: &str = "url.ssh://git@10.10.0.216:2222/.insteadOf";
pub const HANDSHAKE_REWRITE_KEY: &str = "url.ssh://git@gitlab-via-handshake/.insteadOf";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClientMode {
    Handshake,
    Direct,
    Mixed,
    Unconfigured,
}

pub struct RewriteValues<'a> {
    pub direct_instead_of: &'a [&'a str],
    pub handshake_instead_of: &'a [&'a str],
}

pub fn detect_mode(values: RewriteValues<'_>) -> ClientMode {
    let direct_to_handshake = values.direct_instead_of.contains(&DIRECT_PREFIX);
    let handshake_to_direct = values.handshake_instead_of.contains(&HANDSHAKE_PREFIX);

    match (direct_to_handshake, handshake_to_direct) {
        (true, true) => ClientMode::Mixed,
        (true, false) => ClientMode::Handshake,
        (false, true) => ClientMode::Direct,
        (false, false) => ClientMode::Unconfigured,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn declares_direct_and_handshake_prefixes() {
        assert_eq!(DIRECT_PREFIX, "ssh://git@10.10.0.216:2222/");
        assert_eq!(HANDSHAKE_PREFIX, "ssh://git@gitlab-via-handshake/");
    }

    #[test]
    fn detects_handshake_mode() {
        let mode = detect_mode(RewriteValues {
            direct_instead_of: &[DIRECT_PREFIX],
            handshake_instead_of: &[],
        });

        assert_eq!(mode, ClientMode::Handshake);
    }

    #[test]
    fn detects_direct_mode() {
        let mode = detect_mode(RewriteValues {
            direct_instead_of: &[],
            handshake_instead_of: &[HANDSHAKE_PREFIX],
        });

        assert_eq!(mode, ClientMode::Direct);
    }

    #[test]
    fn detects_mixed_and_unconfigured_modes() {
        let mixed = detect_mode(RewriteValues {
            direct_instead_of: &[DIRECT_PREFIX],
            handshake_instead_of: &[HANDSHAKE_PREFIX],
        });
        let unconfigured = detect_mode(RewriteValues {
            direct_instead_of: &[],
            handshake_instead_of: &[],
        });

        assert_eq!(mixed, ClientMode::Mixed);
        assert_eq!(unconfigured, ClientMode::Unconfigured);
    }
}
