# Test Matrix Provenance

This file records the provenance and licensing boundary of canonical HACP reproduction assets included in `hacp-sidecar-ada`.

The public reproduction is version-driven. Git commit and blob identities below document provenance; they are **not execution selectors**.

## Canonical HACP conformance material

Source repository:

`https://github.com/digital-humanism/hacp-spec`

Source branch:

`RELEASE/1.1.1`

Source HEAD captured for this public snapshot:

`61d247d8c833af8f516844cb25f62fd34f1954ca`

Source worktree at capture:

`clean`

Exact transfer verification:

`108 / 108 canonical target files matched hacp-spec by SHA-256`

Unmatched canonical files:

`0`

### Harness

Public path:

`harness/`

Source path:

`hacp-spec/harness/`

Transferred files:

- `conformance_manifest.json`
- `enforcement_v2_runner.py`
- `harness_runner.py`
- `harness.py`
- `protocol_v1_verifier.py`
- `requirements.txt`
- `keys/KEYS.md`
- `keys/test-ed25519-001.pub`
- `keys/test-ed25519-001.seed`

All transferred bytes were verified by SHA-256 against the source repository at the recorded source HEAD.

### Schemas

Public path:

`schemas/`

Source path:

`hacp-spec/schemas/`

Schema files:

- `agency_decision.json`
- `decision_token.json`
- `intent_envelope.json`
- `proposed_action.json`
- `provenance_event.json`
- `revocation_record.json`

All six files were verified by SHA-256 against the source repository.

### HACP-Core vectors

Public path:

`vectors/core/`

Source path:

`hacp-spec/vectors/`

Canonical vector set:

`core-0.9.2`

Canonical file count:

`38`

All 38 files were verified by SHA-256 against the source repository.

### HC2 enforcement-v2 vectors

Public path:

`vectors/enforcement-v2/`

Source path:

`hacp-spec/vectors/enforcement-v2/`

Canonical file count:

`55`

All 55 files were verified by SHA-256 against the source repository.

## Licensing of canonical HACP material

The `hacp-spec` license surface captured with this snapshot states that the HACP Specification, including normative documents, JSON schemas, conformance suites, and architectural texts in that repository, is licensed under **Creative Commons Attribution 4.0 International (CC BY 4.0)**.

These copied canonical assets are not relicensed merely because they are present inside this repository.

The Ada/SPARK implementation code and newly created Ada-specific reproduction tooling are governed by this repository's software licensing surface.

## HTTP workload observer

Public path:

`test/matrix/t_ada/HTTP/observer/main.go`

Canonical source repository:

`https://github.com/digital-humanism/hacp-sidecar`

Source branch:

`RELEASE/1.1.1`

Source HEAD:

`98924b90bdb720d4eaa9903b9456d21ade485fd1`

Source path:

`benchmarks/rust-http-reproduction/main.go`

Source-introduction commit:

`3018b6bac9753bb7bc4c090d54de71f8bd5cb2f9`

Source blob:

`69b2d8f1de4e8dd6a5c3f67e73b6a4fa0bdaaa58`

Copied-file SHA-256:

`C52125CEA8CE959FBE613063E9370AE1E63F92F2CC755CEEAC1AD338B5FAB895`

Role:

`HTTP local-response workload observer / client`

Pinned behavioral contract:

- 100 warm-up requests
- 5,000 measured requests
- concurrency 1
- HTTP 200
- `X-HACP-Decision: ALLOW`

- timing informational only

Source repository licensing:

`AGPLv3 + commercial dual licensing`

The observer is repository-owned verification tooling and is not a separate HACP implementation dependency.

## Execution boundary

Normal public reproduction does not require local checkouts of:

- `hacp-spec`
- `hacp-sidecar`
- `humanist-core`
- the internal `hacp-spark` laboratory workspace

Those repositories are provenance, normative, architectural, or project references only.
