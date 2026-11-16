# humanist-core Observable Parity

This family reproduces the bounded observable `humanist-core` cases used during
Ada semantic verification.

It does not claim:

- full Python API equivalence;
- full `humanist-core` unit-test-suite reproduction;
- literal source-port equivalence.

Some cases are already executed directly by the canonical Core family.

Dedicated cases not represented directly by canonical vectors are reconstructed
at reproduction time as fresh repository-owned bounded witnesses.

Historical temporary witness files are not public dependencies and no byte
identity with those temporary files is claimed.

Fresh witness derivations include:

- `CORE-RUNTIME-004` -> checkpoint `RESOLVED_DENY`
- `CORE-RUNTIME-004` -> unknown checkpoint state
- `CORE-INV4-005` -> malformed/non-object provenance
- `CORE-INV1-001` -> untrusted DecisionToken signer
- `CORE-INV2-006` -> missing destination

Required final disposition:

```text
CHECKPOINT_PARITY=RESTORED
SCOPE_PARITY=RESTORED
KNOWN_HUMANIST_CORE_SEMANTIC_PARITY_GAPS=0
KNOWN_SEMANTIC_RED=NONE
```

This family intentionally has no synthetic numeric total.
