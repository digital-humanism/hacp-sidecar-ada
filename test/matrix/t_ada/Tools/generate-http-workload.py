#!/usr/bin/env python3
"""
Generate fresh signed HTTP workload fixtures for the Ada/SPARK HACP runtime.

Method reproduced from the established HACP HTTP workload contract:

- one fixed signed IntentEnvelope per generated fixture file;
- one fixed HTTP ProposedAction shape;
- one fixed action_hash for that shape;
- unique token_id per request;
- freshly signed DecisionToken per request;
- TTL = 7200 seconds;
- JSONL output records contain base64url envelope/token headers.

Canonicalization, hashing, and signing helpers are imported from the
canonical HACP conformance harness. No independent crypto contract is
implemented here.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import time
import uuid
from pathlib import Path


THIS_FILE = Path(__file__).resolve()
MATRIX_DIR = THIS_FILE.parents[2]
REPO_ROOT = MATRIX_DIR.parent.parent
HARNESS_DIR = REPO_ROOT / "harness"
KEYS_DIR = HARNESS_DIR / "keys"

sys.path.insert(0, str(HARNESS_DIR))

import harness  # noqa: E402


KEY_ID = "key-ed25519-test-001"
EXPECTED_PUBLIC_KEY_HEX = (
    "9d17f1bbcc0845865e670f526413fb7a"
    "510380798fe300b6c98e28f3a3b0fdb3"
)
SEED_FILE = KEYS_DIR / "test-ed25519-001.seed"
PUBLIC_KEY_FILE = KEYS_DIR / "test-ed25519-001.pub"

ENVELOPE_ID = "22222222-2222-2222-2222-222222222222"
PRINCIPAL = "human_admin_01"

POLICY_DIGEST = (
    "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"
    "a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
)

TTL_SECONDS = 7200


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def compact_json(obj: dict) -> bytes:
    return json.dumps(
        obj,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")


def method_to_verb(method: str) -> str:
    value = method.upper()

    if value in ("GET", "HEAD"):
        return "read"

    if value in ("POST", "PUT", "PATCH"):
        return "write"

    if value == "DELETE":
        return "delete"

    return "unknown"


def load_private_key():
    if not harness.HAS_CRYPTO or harness.Ed25519PrivateKey is None:
        raise RuntimeError(
            "cryptography Ed25519 support is required"
        )

    seed_hex = SEED_FILE.read_text(encoding="utf-8").strip()
    seed = bytes.fromhex(seed_hex)

    if len(seed) != 32:
        raise RuntimeError(
            f"canonical Ed25519 seed must be 32 bytes, got {len(seed)}"
        )

    private_key = harness.Ed25519PrivateKey.from_private_bytes(seed)

    public_hex = PUBLIC_KEY_FILE.read_text(
        encoding="utf-8"
    ).strip().lower()

    if public_hex != EXPECTED_PUBLIC_KEY_HEX:
        raise RuntimeError(
            "canonical public key does not match Ada runtime key"
        )

    return private_key


def sign_object(obj: dict, private_key) -> dict:
    unsigned = dict(obj)

    unsigned.pop("signature", None)

    signed = dict(unsigned)
    signed["signature"] = harness.sign_payload(
        harness.canonicalize(unsigned),
        private_key,
    )

    return signed


def verify_object_signature(obj: dict, public_key) -> None:
    unsigned = {
        key: value
        for key, value in obj.items()
        if key != "signature"
    }

    if not harness.verify_signature(
        harness.canonicalize(unsigned),
        obj["signature"],
        public_key,
    ):
        raise RuntimeError("generated signature verification failed")


def build_envelope(
    now: int,
    expires: int,
    private_key,
) -> dict:
    scope = {
        "verbs": ["read"],
        "resource_classes": ["customer_record"],
        "audiences": ["internal"],
        "reversibility": ["reversible"],
        "externality": ["internal"],
        "data_classes": ["internal"],
    }

    envelope = {
        "hacp_version": "0.9",
        "envelope_id": ENVELOPE_ID,
        "principal": PRINCIPAL,
        "principal_kind": "human",
        "intent_statement": "Benchmark envelope",
        "scope": scope,
        "issued_at": now,
        "expires_at": expires,
        "signer_key_id": KEY_ID,
    }

    return sign_object(envelope, private_key)


def build_action(method: str, path: str) -> dict:
    return {
        "hacp_version": "0.9",
        "verb": method_to_verb(method),
        "resource_class": "customer_record",
        "resource_id": path,
        "audience": "internal",
        "reversibility": "reversible",
        "externality": "internal",
        "data_class": "internal",
        "payload_hash": harness.compute_sha256(b""),
    }


def build_token(
    action_hash: str,
    method: str,
    path: str,
    now: int,
    expires: int,
    private_key,
) -> dict:
    token = {
        "hacp_version": "0.9",
        "token_id": str(uuid.uuid4()),
        "envelope_id": ENVELOPE_ID,
        "action_hash": action_hash,
        "policy_digest": POLICY_DIGEST,
        "principal": PRINCIPAL,
        "signer_key_id": KEY_ID,
        "issued_at": now,
        "expires_at": expires,
        "decision": "ALLOW",
        "constraints": {
            "method": method,
            "path": path,
            "max_uses": 99999,
        },
    }

    return sign_object(token, private_key)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Generate signed Ada HTTP reproduction workload fixtures."
        )
    )

    parser.add_argument(
        "-count",
        "--count",
        type=int,
        default=1000,
        help="number of token pairs to generate",
    )

    parser.add_argument(
        "-out",
        "--out",
        type=Path,
        default=Path("tokens.jsonl"),
        help="JSONL output file",
    )

    parser.add_argument(
        "-method",
        "--method",
        default="GET",
        help="HTTP method",
    )

    parser.add_argument(
        "-path",
        "--path",
        default="/api/test",
        help="HTTP request path",
    )

    args = parser.parse_args()

    if args.count <= 0:
        raise RuntimeError("count must be greater than zero")

    method = args.method.upper()
    path = args.path

    private_key = load_private_key()
    key_loader = harness.KeyLoader()

    now = int(time.time())
    expires = now + TTL_SECONDS

    envelope = build_envelope(
        now,
        expires,
        private_key,
    )

    verify_object_signature(
        envelope,
        key_loader.public_key,
    )

    action = build_action(method, path)

    action_hash = harness.compute_sha256(
        harness.canonicalize(action)
    )

    env_header = base64url(
        compact_json(envelope)
    )

    args.out.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    token_ids: set[str] = set()

    with args.out.open(
        "w",
        encoding="utf-8",
        newline="\n",
    ) as handle:
        for _ in range(args.count):
            token = build_token(
                action_hash,
                method,
                path,
                now,
                expires,
                private_key,
            )

            token_id = token["token_id"]

            if token_id in token_ids:
                raise RuntimeError(
                    f"duplicate generated token_id: {token_id}"
                )

            token_ids.add(token_id)

            verify_object_signature(
                token,
                key_loader.public_key,
            )

            if token["action_hash"] != action_hash:
                raise RuntimeError(
                    "generated token action_hash mismatch"
                )

            record = {
                "env": env_header,
                "tok": base64url(
                    compact_json(token)
                ),
            }

            handle.write(
                json.dumps(
                    record,
                    separators=(",", ":"),
                )
            )
            handle.write("\n")

    print(f"OUTPUT={args.out}")
    print(f"COUNT={args.count}")
    print(f"METHOD={method}")
    print(f"PATH={path}")
    print(f"TTL_SECONDS={TTL_SECONDS}")
    print(f"ISSUED_AT={now}")
    print(f"EXPIRES_AT={expires}")
    print(f"ENVELOPE_ID={ENVELOPE_ID}")
    print(f"UNIQUE_TOKEN_IDS={len(token_ids)}")
    print(f"ACTION_HASH={action_hash}")
    print("SIGNATURE_SELF_CHECK=PASS")
    print("HTTP_WORKLOAD_GENERATION=PASS")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
