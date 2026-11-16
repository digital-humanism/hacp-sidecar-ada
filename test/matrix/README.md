# HACP Ada Public Test Matrix

The Ada/SPARK public reproduction uses the same controlled matrix principle as
the HACP project:

```text
00 Preflight
01 Prepare Environment / Build
02 Run Verification
03 Postflight
04 Reconcile Results
05 Generate Markdown Report
human review
```

Run from the repository root:

```powershell
pwsh -File .\test\matrix\t_ada\Scripts\00-Preflight.ps1
pwsh -File .\test\matrix\t_ada\Scripts\01-Prepare-Environment.ps1
pwsh -File .\test\matrix\t_ada\Scripts\02-Run-Verification.ps1
pwsh -File .\test\matrix\t_ada\Scripts\03-Postflight.ps1
pwsh -File .\test\matrix\t_ada\Scripts\04-Reconcile-Results.ps1
pwsh -File .\test\matrix\t_ada\Scripts\05-Generate-Report.ps1
```

## Evidence families

The matrix preserves independent evidence accounting:

```text
HACP Core             38/38
HC2                    55/55
Authorization-v2        3/3
humanist-core parity    targeted documented cases; no synthetic total
Runtime                  5/5
HTTP functional          PASS
HTTP workload            100/100 warmup + 5000/5000 measured
```

No synthetic total is created across these families.

## Canonical material

Canonical harness, schemas, vectors, and deterministic HACP key material are
repository-owned copies originating from `hacp-spec`.

See `PROVENANCE.md`.

## Generated data

Authorization-v2, parity, and HTTP workload material is generated at
reproduction time.

Generated files and result records are written outside the tracked repository
or removed after execution.

After successful reconciliation, `05-Generate-Report.ps1` writes a complete
Markdown reproduction report under the current user's temporary directory:

```text
%TEMP%\hacp-sidecar-ada\reports\
```

The script prints the exact absolute report path as `REPORT_PATH=...`.

Historical development-time temporary witness files are not public
dependencies.

## Failure handling

Any failed evidence family fails the verification stage.

The scripts do not:

- repair source automatically;
- modify canonical vectors;
- authorize release automatically;
- convert timing measurements into normative acceptance thresholds.

A successful reconciliation still requires a human release-control decision.
