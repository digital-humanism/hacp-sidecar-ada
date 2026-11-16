# hacp-sidecar-ada

![Release](https://img.shields.io/badge/HACP-1.1.1-334155?style=flat-square)
![Ada](https://img.shields.io/badge/Ada%20%2F%20SPARK-implementation-334155?style=flat-square)
![Core](https://img.shields.io/badge/HACP--Core-38%2F38%20PASS-16784a?style=flat-square)
![HC2](https://img.shields.io/badge/HC2--55-55%2F55%20PASS-16784a?style=flat-square)
![Authorization](https://img.shields.io/badge/Authorization--v2-3%2F3%20PASS-16784a?style=flat-square)
![License](https://img.shields.io/badge/License-AGPLv3%20%2B%20Commercial-334155?style=flat-square)
[![Ada Fast CI](https://github.com/digital-humanism/hacp-sidecar-ada/actions/workflows/ci.yml/badge.svg?branch=RELEASE%2F1.1.1)](https://github.com/digital-humanism/hacp-sidecar-ada/actions/workflows/ci.yml?query=branch%3ARELEASE%2F1.1.1)
[![Public reproduction](https://img.shields.io/badge/Public%20reproduction-verified-brightgreen)](https://github.com/digital-humanism/hacp-sidecar-ada/actions/workflows/ci.yml?query=branch%3ARELEASE%2F1.1.1)

Ada/SPARK independent HACP sidecar reproduction within the HUMANIST / HACP project.

This repository provides a technically self-contained Ada/SPARK implementation and public reproduction surface for the HACP 1.1.1 release composition.

## Project relationship

HACP protocol semantics and conformance definitions are governed by [`hacp-spec`](https://github.com/digital-humanism/hacp-spec).

Related HUMANIST / HACP project repositories:

- [`hacp-spec`](https://github.com/digital-humanism/hacp-spec) — normative protocol and conformance authority.
- [`hacp-sidecar`](https://github.com/digital-humanism/hacp-sidecar) — enforcement-sidecar architecture and implementation reference.
- [`humanist-core`](https://github.com/digital-humanism/humanist-core) — reference SDK and project-composition surface.

These are project and documentary relationships, not local execution dependencies.

## Release identity

```text
repository : hacp-sidecar-ada
release    : 1.1.1
branch     : RELEASE/1.1.1
```

This reproduction is **version-driven, not SHA-driven**.

## Verified evidence

```text
Core                 : 38/38 PASS
HC2                  : 55/55 PASS
Authorization-v2     : 3/3 PASS
Runtime              : 5/5 PASS
HTTP negative        : PASS
HTTP single valid    : PASS
HTTP canonical load  : 100/100 warmup + 5000/5000 measured
humanist-core parity : targeted documented cases reproduced; known semantic RED none
```

Evidence families are reported separately. No synthetic total is used.

Timing measurements are observational and are not normative HACP acceptance thresholds.

## Reproduction

The complete public reproduction workflow is under:

[`test/matrix/README.md`](test/matrix/README.md)

The intended public workflow is:

```text
00 Preflight
01 Prepare Environment / Build
02 Run Verification
03 Postflight
04 Reconcile Results
human review
```

No stage automatically authorizes the next release-control action.

## Current status and boundaries

This repository is an Ada/SPARK HACP implementation and reproduction surface.

It does **not** claim:

- full Python API equivalence with `humanist-core`;
- literal source-port equivalence with `humanist-core`;
- reproduction of the complete Python regression suite;
- automatic replacement of `hacp-sidecar`;
- current registration as an additional official `hacp-spec` implementation.

The repository is structured so a future implementation-registration step can be documentary/compositional rather than an architectural redesign.

## Canonical test material

Canonical HACP harness, schemas, vectors, and deterministic test-key material included in this repository are copied from `hacp-spec` and retain their applicable provenance and licensing.

See:

[`test/matrix/PROVENANCE.md`](test/matrix/PROVENANCE.md)

## License

### Open-source license

Repository-owned Ada/SPARK implementation code and Ada-specific reproduction tooling are licensed under the GNU Affero General Public License v3.0, with the project software surface represented as `AGPL-3.0-or-later`.

See [`LICENSE.md`](LICENSE.md).

### Commercial licensing

A commercial licensing path is also available under the HUMANIST / HACP project licensing model.

See [`COMMERCIAL.md`](COMMERCIAL.md).

### AGPLv3 notice for network deployment

Under AGPLv3 §13, any network-accessible deployment of this sidecar that serves external users requires the source code of the deployed version (including any modifications) to be made available to those users. Commercial licenses waive this requirement.
