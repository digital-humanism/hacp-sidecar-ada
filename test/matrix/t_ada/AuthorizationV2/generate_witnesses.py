#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path


THIS_FILE = Path(__file__).resolve()
T_ADA = THIS_FILE.parents[1]
MATRIX = T_ADA.parent
REPO_ROOT = MATRIX.parent.parent
HARNESS_DIR = REPO_ROOT / "harness"
CORE_DIR = REPO_ROOT / "vectors" / "core"
KEYS_DIR = HARNESS_DIR / "keys"

sys.path.insert(0, str(HARNESS_DIR))

import harness  # noqa: E402


BASE_VECTOR = CORE_DIR / "core_inv1_001_golden.json"
SEED_FILE = KEYS_DIR / "test-ed25519-001.seed"

EXPECTED_PUBLIC_KEY_HEX = (
    "9d17f1bbcc0845865e670f526413fb7a"
    "510380798fe300b6c98e28f3a3b0fdb3"
)


def load_base() -> dict:
    with BASE_VECTOR.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def private_key():
    if not harness.HAS_CRYPTO or harness.Ed25519PrivateKey is None:
        raise RuntimeError("cryptography Ed25519 support is required")

    seed = bytes.fromhex(SEED_FILE.read_text(encoding="utf-8").strip())

    if len(seed) != 32:
        raise RuntimeError("canonical Ed25519 seed must be 32 bytes")

    key_loader = harness.KeyLoader()

    public_hex = (
        KEYS_DIR / "test-ed25519-001.pub"
    ).read_text(
        encoding="utf-8"
    ).strip().lower()

    if public_hex != EXPECTED_PUBLIC_KEY_HEX:
        raise RuntimeError("canonical public key mismatch")

    if key_loader.public_key is None:
        raise RuntimeError("canonical public key could not be loaded")

    return harness.Ed25519PrivateKey.from_private_bytes(seed)


def resign(obj: dict, key) -> dict:
    unsigned = dict(obj)
    unsigned.pop("signature", None)

    signed = dict(unsigned)
    signed["signature"] = harness.sign_payload(
        harness.canonicalize(unsigned),
        key,
    )

    return signed


def as_public_witness(base: dict, name: str) -> dict:
    return {
        "witness_id": name,
        "input": copy.deepcopy(base["inputs"]),
        "policy_context": copy.deepcopy(
            base.get("policy_context", {})
        ),
    }


def write_json(path: Path, value: dict) -> None:
    path.write_text(
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        type=Path,
        required=True,
    )
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)

    base = load_base()
    key = private_key()

    # ------------------------------------------------------------
    # Witness 1:
    # presented ProposedAction changes after token issuance.
    # Existing signed DecisionToken is intentionally preserved.
    # ------------------------------------------------------------

    action_hash = as_public_witness(
        base,
        "ACTION_HASH_WITNESS",
    )

    action_hash["input"]["proposed_action"]["resource_id"] = (
        "db://prod/changed-after-token-issuance"
    )

    # ------------------------------------------------------------
    # Witness 2:
    # invalid IntentEnvelope signature.
    # Historical reproduction used 64 zero bytes encoded as hex.
    # ------------------------------------------------------------

    bad_envelope = as_public_witness(
        base,
        "ENVELOPE_SIGNATURE_WITNESS",
    )

    bad_envelope["input"]["intent_envelope"]["signature"] = (
        "00" * 64
    )

    # ------------------------------------------------------------
    # Witness 3:
    # authenticated signed DENY.
    # DecisionToken must be re-signed after decision mutation.
    # ------------------------------------------------------------

    signed_deny = as_public_witness(
        base,
        "SIGNED_DENY_WITNESS",
    )

    token = signed_deny["input"]["decision_token"]
    token["decision"] = "DENY"

    signed_deny["input"]["decision_token"] = resign(
        token,
        key,
    )

    witnesses = {
        "ACTION_HASH_WITNESS": action_hash,
        "ENVELOPE_SIGNATURE_WITNESS": bad_envelope,
        "SIGNED_DENY_WITNESS": signed_deny,
    }

    for name, witness in witnesses.items():
        path = args.out / f"{name.lower()}.json"
        write_json(path, witness)
        print(f"WITNESS={name} | FILE={path}")

    print("AUTH_V2_WITNESS_GENERATION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
