# HACP Sidecar Ada — Runtime Topology and Process Lifecycle

**Repository:** `digital-humanism/hacp-sidecar-ada`  
**Release line:** HACP 1.1.1  
**Implementation:** Ada/SPARK  
**Document class:** Public implementation note  
**Status:** Active  
**Applies to:** Public build, verification, and reproduction surfaces

---

## 1. Purpose

This document explains the runtime topology of the Ada/SPARK HACP sidecar reproduction.

The public verification matrix exercises several executable surfaces, but not every executable surface is a network server. Some are request/response processes, some use standard input/output as their transport, and the managed HTTP surface is the component that opens a local TCP listener.

This distinction is intentional.

The verification design uses the smallest runtime boundary necessary for each surface while preserving the observable HACP behavior being tested.

---

## 2. Runtime Topology at a Glance

| Surface | Executable | Runtime boundary | Network listener | Verification role |
| --- | --- | --- | --- | --- |
| Core runner | `hacp_ada_runner.exe` | Process request/response | No | Canonical HACP-Core and HC2 evaluation |
| Authorization-v2 runner | `hacp_ada_auth_v2_runner.exe` | Process request/response | No | Authorization-v2 witness verification |
| Managed HTTP proxy | `hacp_ada_proxy.exe` | HTTP over loopback TCP | **Yes** | HTTP enforcement and managed workload reproduction |
| MCP surface | `hacp_ada_mcp.exe` | STDIO | No | MCP transport behavior |
| Control-plane surface | `hacp_ada_controlplane.exe` | STDIO | No | Control-state snapshot and event behavior |
| Integrated runtime | `hacp_ada_integrated.exe` | Process execution | No separate listener required by the public matrix | Integrated control-state / revocation behavior |

The public matrix therefore does **not** start a collection of visible long-running server consoles.

Only the managed HTTP proxy requires a TCP listening socket for its verification path.

---

## 3. Managed HTTP Surface

The managed HTTP surface is implemented by:

```text
bin/hacp_ada_proxy.exe
```

It is the network-facing runtime used by the public HTTP reproduction.

The public wrapper:

```text
test/matrix/t_ada/HTTP/run-http-reproduction.ps1
```

owns the complete lifecycle:

```text
select free loopback TCP port
        ↓
start hacp_ada_proxy.exe
        ↓
wait for local readiness
        ↓
verify unsigned request → HTTP 403 / HACP DENY
        ↓
verify signed request → HTTP 200 / HACP ALLOW
        ↓
run warmup workload
        ↓
run measured workload
        ↓
stop the owned proxy process
        ↓
remove temporary workload material
```

The port is selected dynamically from an available loopback TCP port. The public reproduction does not require a fixed port such as `18081`.

The service is bound to the local verification topology and is not intended to become an externally exposed deployment merely because the test matrix starts it.

---

## 4. Managed HTTP Verification Contract

The public HACP 1.1.1 Ada reproduction verifies the following functional boundary:

```text
request without required HACP authorization material
→ HTTP 403
→ X-HACP-Decision: DENY
```

and:

```text
valid signed request
→ HTTP 200
→ X-HACP-Decision: ALLOW
```

The managed workload then verifies:

```text
warmup:
100 requests
100 success
0 failed

measured:
5000 requests
5000 success
0 failed

concurrency:
1
```

The workload is deliberately serial.

Performance timing collected during this reproduction is observational evidence only. It is not a normative HACP latency requirement and is not a release acceptance threshold.

---

## 5. Core Evaluation Runner

The Core runner:

```text
bin/hacp_ada_runner.exe
```

does not open a public network listener.

It is used as a deterministic process boundary for canonical HACP evaluation.

The public verification surface uses it for:

```text
HACP-Core
38/38 canonical vectors

HC2-55
55/55 canonical vectors
```

The runner provides an implementation execution boundary while allowing the canonical verification harness to remain responsible for:

- vector loading;
- schema and manifest checks;
- request construction;
- response verification;
- evidence accounting.

This is an implementation process surface, not a daemon deployment model.

---

## 6. Authorization-v2 Runner

The Authorization-v2 runner:

```text
bin/hacp_ada_auth_v2_runner.exe
```

is also a process request/response surface.

It is used by the public matrix to verify three independently generated witnesses:

```text
ACTION_HASH_WITNESS
ENVELOPE_SIGNATURE_WITNESS
SIGNED_DENY_WITNESS
```

The current public evidence contract is:

```text
3/3 PASS
```

No network service is required for this verification family.

---

## 7. MCP Runtime Surface

The MCP executable:

```text
bin/hacp_ada_mcp.exe
```

is exercised through **STDIO**.

The public runtime matrix verifies the implementation transport behavior through a process-local standard-input / standard-output interaction.

The verified runtime result is represented as:

```text
MCP_RESULT=HACP ALLOW
MCP_INPUT_CLASS=IMPLEMENTATION_TRANSPORT_FIXTURE
```

This surface therefore does not require a TCP listener or a separately visible server process.

STDIO is the transport boundary for the public reproduction.

---

## 8. Control-Plane Runtime Surface

The control-plane executable:

```text
bin/hacp_ada_controlplane.exe
```

is also exercised through **STDIO**.

The public runtime verification checks observable control-state behavior including:

```text
control revision
snapshot contents
event availability
```

The verified public runtime state includes:

```text
CONTROL_REVISION=1
CONTROL_SNAPSHOT_ENTRIES=1
CONTROL_EVENTS_AFTER_0=1
```

The control-plane test is therefore a process/STDIO verification surface rather than a network service deployment.

This distinction does not redefine the HACP control-plane architecture. It describes the transport used by this public Ada reproduction to verify the relevant observable behavior.

---

## 9. Integrated Runtime Surface

The integrated executable:

```text
bin/hacp_ada_integrated.exe
```

is used to verify behavior that spans evaluation and control-state changes.

The public matrix currently verifies an integrated revocation flow:

```text
baseline evaluation
→ ALLOW

revocation committed
→ control-state revision advances

same authorization context after revocation
→ DENY
→ TOKEN_REVOKED
```

The integrated verification does not require a separate long-running network listener.

Its purpose is to demonstrate observable interaction between the relevant implementation components within one controlled runtime flow.

---

## 10. Runtime Surface Accounting

The public HACP 1.1.1 Ada matrix reports five runtime surfaces:

```text
1. Canonical Core runtime vectors
2. Managed HTTP transport
3. MCP STDIO
4. Control-plane STDIO
5. Integrated revocation flow
```

The historical internal runtime numbering may contain identifiers such as `RUNTIME-6`. Those identifiers are retained for evidence continuity and do not imply that six active public runtime surfaces are claimed.

The public acceptance value is:

```text
RUNTIME=5/5 PASS
```

---

## 11. Process Ownership

Every process started by the public verification surface has an explicit owner.

The general rule is:

```text
verification wrapper starts the process
verification wrapper owns the process
verification wrapper stops the process
```

The matrix must not depend on a developer manually starting an Ada runtime service before verification.

Likewise, successful verification must not leave implementation processes running after the owning test family has completed.

The full public matrix verifies cleanup after execution.

Expected final state:

```text
REMAINING_ADA_PROCESS_COUNT=0
```

The dedicated managed HTTP wrapper additionally removes its temporary workload directory after the proxy is stopped.

---

## 12. Why Server Windows May Not Be Visible

The public verification scripts start runtime processes programmatically.

They do not normally launch separate interactive console windows.

Consequently, during a normal matrix run a user may see:

```text
HTTP_STARTUP_READY_MS=...
HTTP_STATUS=200
HTTP_DECISION=ALLOW
```

or workload results such as:

```text
R8_2_WORKLOAD=PASS
```

without seeing a persistent server terminal on the desktop.

This is expected.

The evidence of a network service is the successful listener readiness and completed HTTP interaction, not the presence of a separately visible console window.

---

## 13. Runtime vs. Deployment

The topology described here is the **public reproduction topology**.

It should not be interpreted as a requirement that every production integration use the same process layout.

In particular:

- the Core runner is a verification execution surface;
- MCP and control-plane verification currently use STDIO;
- the managed HTTP proxy is the network-facing public runtime surface;
- integrated verification uses a bounded process flow;
- production isolation, supervision, service management, and network exposure remain deployment concerns.

HACP conformance and deployment architecture are related but distinct concerns.

---

## 14. No Hidden Cross-Repository Runtime Dependency

The public runtime matrix is designed to execute from the `hacp-sidecar-ada` repository using repository-owned verification assets and explicitly declared external toolchain dependencies.

Successful runtime verification must not require a local checkout of:

```text
hacp-spec
hacp-sidecar
humanist-core
internal Ada/SPARK laboratory workspace
```

References to other HUMANIST/HACP repositories may remain in documentation for normative, architectural, licensing, provenance, or project-composition purposes.

Such references are not runtime execution dependencies.

---

## 15. SHA Usage

The public runtime output may display SHA-256 values for:

- canonical conformance integrity;
- generated or transferred fixture identity;
- built executable identity;
- passive evidence provenance.

These hashes do not select the public implementation, build, dependency version, snapshot, or release.

The reproduction model remains:

```text
VERSION-DRIVEN
NOT SHA-DRIVEN
```

Hashes verify identity or integrity where appropriate; they do not serve as operational version selectors.

---

## 16. Evidence Boundaries

The public runtime topology supports separate evidence families.

It does not create a synthetic aggregate test count.

Current public evidence is reported independently as:

```text
HACP-Core:
38/38 PASS

HC2-55:
55/55 PASS

Authorization-v2:
3/3 PASS

humanist-core observable parity:
targeted documented cases reproduced
no synthetic total

Runtime:
5/5 PASS

Managed HTTP:
100/100 warmup
5000/5000 measured
0 failures
concurrency 1
```

---

## 17. What This Document Does Not Claim

This document does not claim that:

- every executable is a network server;
- all runtime surfaces must be deployed as independent services;
- the Ada implementation reproduces the full Python API of `humanist-core`;
- the Ada implementation is a literal port of another implementation;
- timing observations define HACP protocol requirements;
- the Ada implementation has already been registered as a fifth official `hacp-spec` implementation.

It documents the public Ada runtime topology and the lifecycle used by the HACP 1.1.1 reproduction matrix.

---

## 18. Summary

The public Ada/SPARK sidecar reproduction uses several runtime boundaries, but only one of them is a managed network listener in the current public matrix.

```text
Managed HTTP proxy
    network server
    loopback TCP
    wrapper-owned lifecycle

Core runner
    process request/response

Authorization-v2 runner
    process request/response

MCP
    STDIO

Control plane
    STDIO

Integrated runtime
    bounded process flow
```

This topology is intentional, reproducible, and aligned with the evidence each surface is responsible for proving.

The public verification matrix owns startup, execution, cleanup, and result accounting so that reproduction does not depend on manually pre-started local services.
