# Ada/SPARK Verification Surface

This directory contains the Ada/SPARK public reproduction entrypoints.

The implementation is tested using repository-owned canonical HACP assets and
version-pinned external dependencies. Normal reproduction does not require
local checkouts of `hacp-spec`, `hacp-sidecar`, `humanist-core`, or the internal
Ada laboratory workspace.

Public execution is coordinated through `Scripts/`.

Individual evidence-family entrypoints remain independently executable so their
results are not collapsed into a synthetic aggregate.
