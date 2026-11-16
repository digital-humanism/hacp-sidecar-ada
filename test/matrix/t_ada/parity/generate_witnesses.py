#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


THIS_FILE = Path(__file__).resolve()
T_ADA = THIS_FILE.parents[1]
MATRIX = T_ADA.parent
REPO_ROOT = MATRIX.parent.parent
CORE_DIR = REPO_ROOT / "vectors" / "core"


def load(name: str) -> dict:
    with (CORE_DIR / name).open(
        "r",
        encoding="utf-8",
    ) as handle:
        return json.load(handle)


def witness(base: dict, witness_id: str) -> dict:
    return {
        "witness_id": witness_id,
        "input": copy.deepcopy(base["inputs"]),
        "policy_context": copy.deepcopy(
            base.get("policy_context", {})
        ),
    }


def save(path: Path, value: dict) -> None:
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

    runtime_open = load("runtime_004_negative.json")
    scope_dest = load("core_inv2_006_negative.json")
    provenance = load("core_inv4_005_negative.json")
    trusted = load("core_inv1_001_golden.json")

    # Fresh public witness:
    # checkpoint state RESOLVED_DENY.
    resolved_deny = witness(
        runtime_open,
        "PARITY_CHECKPOINT_RESOLVED_DENY",
    )
    resolved_deny["input"]["checkpoint"]["state"] = "RESOLVED_DENY"

    # Fresh public witness:
    # unknown checkpoint state.
    unknown_checkpoint = witness(
        runtime_open,
        "PARITY_CHECKPOINT_UNKNOWN_STATE",
    )
    unknown_checkpoint["input"]["checkpoint"]["state"] = (
        "UNKNOWN_STATE"
    )

    # Fresh public witness:
    # malformed/non-object provenance.
    malformed_provenance = witness(
        provenance,
        "PARITY_PROVENANCE_MALFORMED",
    )
    malformed_provenance["input"]["provenance_event"] = (
        "malformed-provenance"
    )

    # Fresh public witness:
    # trusted envelope remains unchanged while token signer becomes unknown.
    untrusted_token = witness(
        trusted,
        "PARITY_TRUST_UNTRUSTED_TOKEN_SIGNER",
    )
    untrusted_token["input"]["decision_token"]["signer_key_id"] = (
        "key-ed25519-unknown-999"
    )

    # Fresh public witness:
    # canonical CORE-INV2-006 minus destination only.
    missing_destination = witness(
        scope_dest,
        "PARITY_SCOPE_MISSING_DESTINATION",
    )
    missing_destination["input"]["proposed_action"].pop(
        "destination",
        None,
    )

    witnesses = {
        "checkpoint_resolved_deny.json": resolved_deny,
        "checkpoint_unknown_state.json": unknown_checkpoint,
        "provenance_malformed.json": malformed_provenance,
        "trust_untrusted_token_signer.json": untrusted_token,
        "scope_missing_destination.json": missing_destination,
    }

    for name, value in witnesses.items():
        save(args.out / name, value)
        print(f"GENERATED={name}")

    print("PARITY_PUBLIC_WITNESS_GENERATION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
