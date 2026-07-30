#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


DEFAULT_BIND = "127.0.0.1"
DEFAULT_PORT = 8787
DEFAULT_TOKEN_FILE = "/etc/handshake-client/tokens"
DEFAULT_AUTHORIZED_KEYS = "/home/gitproxy/.ssh/authorized_keys"
DEFAULT_OPTIONS = 'restrict,port-forwarding,permitopen="127.0.0.1:12222"'
ALLOWED_KEY_TYPES = {
    "ssh-ed25519",
    "ssh-rsa",
    "ecdsa-sha2-nistp256",
    "ecdsa-sha2-nistp384",
    "ecdsa-sha2-nistp521",
}


def env_value(primary, fallback, default):
    return os.environ.get(primary, os.environ.get(fallback, default))


def validate_public_key(public_key):
    key = public_key.strip()
    if "\n" in key or "\r" in key:
        raise ValueError("public key must be a single line")

    fields = key.split()
    if len(fields) < 2:
        raise ValueError("public key must include key type and key body")
    if fields[0] not in ALLOWED_KEY_TYPES:
        raise ValueError(f"unsupported public key type: {fields[0]}")
    if not fields[1]:
        raise ValueError("public key body is empty")
    return key


def load_tokens(path):
    token_path = pathlib.Path(path)
    if not token_path.exists():
        return set()
    tokens = set()
    for line in token_path.read_text(encoding="utf-8").splitlines():
        token = line.strip()
        if token and not token.startswith("#"):
            tokens.add(token)
    return tokens


def consume_token(path, token):
    token_path = pathlib.Path(path)
    tokens = load_tokens(token_path)
    if token not in tokens:
        return False

    tokens.remove(token)
    token_path.parent.mkdir(parents=True, exist_ok=True)
    token_path.write_text("".join(f"{item}\n" for item in sorted(tokens)), encoding="utf-8")
    return True


def append_authorized_key(path, public_key, comment, options):
    key = validate_public_key(public_key)
    safe_comment = " ".join((comment or "").replace("\r", " ").replace("\n", " ").split())
    entry_parts = [part for part in [options.strip(), key, safe_comment] if part]
    entry = " ".join(entry_parts)

    auth_path = pathlib.Path(path)
    auth_path.parent.mkdir(parents=True, exist_ok=True)
    existing = auth_path.read_text(encoding="utf-8").splitlines() if auth_path.exists() else []
    if any(key in line.split("#", 1)[0] for line in existing):
        return False

    with auth_path.open("a", encoding="utf-8") as handle:
        handle.write(entry + "\n")
    os.chmod(auth_path.parent, 0o700)
    os.chmod(auth_path, 0o600)
    return True


def register_key(token_path, authorized_keys_path, token, public_key, comment, options):
    if not token:
        raise PermissionError("token is required")
    key = validate_public_key(public_key)
    if not consume_token(token_path, token):
        raise PermissionError("invalid token")
    return append_authorized_key(authorized_keys_path, key, comment, options)


class AddKeyHandler(BaseHTTPRequestHandler):
    token_path = pathlib.Path(
        env_value("HANDSHAKE_TOKEN_FILE", "ADD_KEY_TOKEN_FILE", DEFAULT_TOKEN_FILE)
    )
    authorized_keys_path = pathlib.Path(
        env_value(
            "HANDSHAKE_AUTHORIZED_KEYS",
            "ADD_KEY_AUTHORIZED_KEYS",
            DEFAULT_AUTHORIZED_KEYS,
        )
    )
    authorized_keys_options = env_value(
        "HANDSHAKE_AUTHORIZED_KEYS_OPTIONS",
        "ADD_KEY_AUTHORIZED_KEYS_OPTIONS",
        DEFAULT_OPTIONS,
    )

    def do_POST(self):
        if self.path != "/keys":
            self.respond_json(404, {"ok": False, "error": "not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            added = register_key(
                self.token_path,
                self.authorized_keys_path,
                str(payload.get("token", "")),
                str(payload.get("public_key", "")),
                str(payload.get("comment", "")),
                self.authorized_keys_options,
            )
            self.respond_json(200, {"ok": True, "added": added})
        except PermissionError as error:
            self.respond_json(403, {"ok": False, "error": str(error)})
        except (ValueError, json.JSONDecodeError) as error:
            self.respond_json(400, {"ok": False, "error": str(error)})

    def do_GET(self):
        if self.path == "/healthz":
            self.respond_json(200, {"ok": True})
        else:
            self.respond_json(404, {"ok": False, "error": "not found"})

    def log_message(self, format, *args):
        return

    def respond_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description="Handshake public-key registration server")
    parser.add_argument(
        "--bind",
        default=env_value("HANDSHAKE_SERVER_BIND", "ADD_KEY_BIND", DEFAULT_BIND),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(env_value("HANDSHAKE_KEY_SERVER_PORT", "ADD_KEY_PORT", str(DEFAULT_PORT))),
    )
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.bind, args.port), AddKeyHandler)
    print(f"add-key server listening on {args.bind}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
