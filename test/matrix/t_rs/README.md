# Ada / Rust Cross-Implementation Reproduction

This directory contains the repository-owned HACP 1.1.1
Ada / Rust cross-implementation reproduction surface.

It provides a single public entrypoint for rebuilding and executing
the bounded Ada and Rust evaluator paths against the canonical
repository-owned HACP vectors.

## Quick start

From the repository root:

```powershell
pwsh -NoProfile -File .\test\matrix\t_rs\Run-Reproduction.ps1
```

No manual execution of the individual numbered scripts is required.

A fresh unique temporary run directory is created automatically.

At successful completion the command prints:

```text
REPRODUCTION RESULT: PASS

ADA_CORE=38/38 PASS
RUST_CORE=38/38 DIRECT PASS
ADA_AUTHORIZATION_V2=3/3 PASS
RUST_AUTHORIZATION_V2=3/3 PASS
CROSS_IMPLEMENTATION_CORE=PASS
CROSS_IMPLEMENTATION_AUTHORIZATION_V2=PASS
KNOWN_SEMANTIC_RED=NONE
SYNTHETIC_TOTAL=NOT_USED

REPORT_MD=<path>
REPORT_HTML=<path>
```

Open the generated HTML report in a browser to inspect the result and
follow the evidence links.

## What is reproduced

### Core

The canonical HACP-Core 0.9.2 vector family is executed independently
against:

- the repository-owned Ada implementation;
- the bounded repository-owned Rust evaluator package.

Expected current result:

```text
Ada Core-compatible:
38/38 PASS

Rust Core-compatible:
38/38 DIRECT PASS
```

The canonical Core vectors remain owned by:

```text
vectors/core/
```

They are not copied into this directory.

## Historical Rust accounting

Historical Rust verification accounting remains:

```text
36 DIRECT + 2 ADJUDICATED / 38
```

The two historical adjudicated cases are:

```text
CORE-INV1-002
CORE-RUNTIME-004
```

This historical record is preserved.

It is not rewritten by the current Core-compatible Rust result.

Both cases now pass directly in the current Ada and Rust
Core-compatible execution paths.

## Authorization-v2

A separate three-witness Authorization-v2 family is reproduced for
both Ada and Rust.

Expected results:

```text
ACTION_HASH_WITNESS
DENY / SIGNATURE_FAILURE

ENVELOPE_SIGNATURE_WITNESS
DENY / SIGNATURE_FAILURE

SIGNED_DENY_WITNESS
DENY / POLICY_DENIED
```

Expected family result:

```text
Ada Authorization-v2:
3/3 PASS

Rust Authorization-v2:
3/3 PASS
```

Core-compatible and Authorization-v2 evidence remain separate.

No synthetic combined total is used.

## Reproduction lifecycle

The public entrypoint executes:

```text
00-Preflight.ps1
        ↓
01-Prepare-Environment.ps1
        ↓
02-Run-Verification.ps1
        ↓
03-Postflight.ps1
        ↓
04-Reconcile-Results.ps1
        ↓
05-Generate-Report.ps1
```

The individual scripts are located under:

```text
test/matrix/t_rs/Scripts/
```

They normally do not need to be invoked manually.

## Repository ownership

The reproduction is self-contained within this repository.

It reuses existing stable repository-owned Ada assets in place.

The bounded Rust package is located at:

```text
test/matrix/t_rs/rust/
```

The existing Ada reproduction matrix is reused where appropriate and
is not modified by this reproduction.

No development laboratory checkout is required.

No sibling repository checkout is required.

Historical source hashes are not used as:

- build selectors;
- dependency selectors;
- implementation selectors;
- release selectors;
- reproduction navigation.

Protocol-intrinsic cryptographic hashing remains part of HACP semantics.

## Rust build

Rust is built from the repository-owned bounded package using its
tracked Cargo lockfile.

The reproduction uses:

```text
cargo ... build --locked --release
```

The two bounded executables are:

```text
hacp-rs-core-runner
hacp-rs-runner
```

## Ada runtime

The Ada implementation is built through the repository-owned Alire /
GPRBuild surface.

On Windows the reproduction resolves the Alire-owned GNAT, GPRBuild,
MinGW runtime and libsodium runtime required by the Ada executables.

## Output

Each execution receives a unique temporary run root.

The generated report bundle contains:

```text
report/
├── HACP_SIDECAR_ADA_RUST_CROSS_IMPLEMENTATION_REPRODUCTION.md
├── HACP_SIDECAR_ADA_RUST_CROSS_IMPLEMENTATION_REPRODUCTION.html
└── _evidence/
    ├── ada_prepare.log
    ├── ada_core.log
    ├── rust_core.log
    ├── ada_authorization_v2.log
    └── rust_authorization_v2.log
```

The HTML report is intended as the primary human-readable verification
surface.

The Markdown report provides the same result in portable text form.

The `_evidence/` directory contains the raw execution evidence used by
the report.

## Controlled RunRoot

Automation may provide an explicit output directory:

```powershell
pwsh -NoProfile `
    -File .\test\matrix\t_rs\Run-Reproduction.ps1 `
    -RunRoot C:\Temp\hacp-t_rs-run
```

If `-RunRoot` is omitted, a unique temporary directory is created.

## PASS contract

A successful reproduction requires all of the following:

```text
ADA_CORE=38/38 PASS
RUST_CORE=38/38 DIRECT PASS

ADA_AUTHORIZATION_V2=3/3 PASS
RUST_AUTHORIZATION_V2=3/3 PASS

CROSS_IMPLEMENTATION_CORE=PASS
CROSS_IMPLEMENTATION_AUTHORIZATION_V2=PASS

KNOWN_SEMANTIC_RED=NONE
SYNTHETIC_TOTAL=NOT_USED
```

Historical Rust accounting remains independently recorded as:

```text
36 DIRECT + 2 ADJUDICATED / 38
```

## Failure behavior

The lifecycle is fail-fast.

If any numbered phase returns a non-zero exit code, execution stops and
the failed phase and run root are printed.

A failed or incomplete run must not be interpreted as a PASS.

## Scope

This reproduction demonstrates bounded cross-implementation evaluator
agreement.

It does not redefine repository roles, protocol ownership, release
status, or licensing boundaries.
