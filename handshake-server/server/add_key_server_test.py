#!/usr/bin/env python3
import pathlib
import tempfile
import unittest

import add_key_server


PUBLIC_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexamplekeydata user@example"
OPTIONS = 'restrict,port-forwarding,permitopen="127.0.0.1:12222"'


class AddKeyServerTest(unittest.TestCase):
    def test_validate_public_key_accepts_common_key_types(self):
        self.assertEqual(add_key_server.validate_public_key(PUBLIC_KEY), PUBLIC_KEY)
        self.assertEqual(
            add_key_server.validate_public_key("ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtest"),
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtest",
        )

    def test_validate_public_key_rejects_malformed_or_injected_keys(self):
        for key in ["", "not-a-key AAAA", "ssh-ed25519", "ssh-ed25519 AAAA\nssh-rsa BBBB"]:
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    add_key_server.validate_public_key(key)

    def test_token_is_consumed_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            token_path = pathlib.Path(tmp) / "tokens"
            token_path.write_text("alpha\nbeta\n", encoding="utf-8")

            self.assertEqual(add_key_server.load_tokens(token_path), {"alpha", "beta"})
            self.assertTrue(add_key_server.consume_token(token_path, "alpha"))
            self.assertFalse(add_key_server.consume_token(token_path, "alpha"))
            self.assertEqual(token_path.read_text(encoding="utf-8"), "beta\n")

    def test_append_authorized_key_formats_and_deduplicates_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            auth_path = pathlib.Path(tmp) / ".ssh" / "authorized_keys"

            first = add_key_server.append_authorized_key(
                auth_path,
                PUBLIC_KEY,
                "teammate@example",
                OPTIONS,
            )
            second = add_key_server.append_authorized_key(
                auth_path,
                PUBLIC_KEY,
                "teammate@example",
                OPTIONS,
            )

            self.assertTrue(first)
            self.assertFalse(second)
            self.assertEqual(
                auth_path.read_text(encoding="utf-8"),
                f'{OPTIONS} {PUBLIC_KEY} teammate@example\n',
            )

    def test_register_key_rejects_invalid_token_before_writing_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            token_path = pathlib.Path(tmp) / "tokens"
            auth_path = pathlib.Path(tmp) / "authorized_keys"
            token_path.write_text("valid-token\n", encoding="utf-8")

            with self.assertRaises(PermissionError):
                add_key_server.register_key(
                    token_path,
                    auth_path,
                    "bad-token",
                    PUBLIC_KEY,
                    "user@example",
                    OPTIONS,
                )

            self.assertFalse(auth_path.exists())


if __name__ == "__main__":
    unittest.main()
