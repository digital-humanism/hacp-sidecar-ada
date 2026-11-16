# Authorization-v2 Reproduction

This family reproduces three bounded Authorization-v2 observable cases:

- changed ProposedAction after token issuance -> `DENY / SIGNATURE_FAILURE`
- invalid IntentEnvelope signature -> `DENY / SIGNATURE_FAILURE`
- authenticated signed-DENY token -> `DENY / POLICY_DENIED`

The witnesses are generated at reproduction time from the canonical
`CORE-INV1-001` input and deterministic HACP test key material.

The historical development-time temporary witness files are not public
dependencies.

Run:

```powershell
pwsh -File .\test\matrix\t_ada\AuthorizationV2\run-witnesses.ps1
```

Required closure:

```text
ACTION_HASH_WITNESS=PASS
ENVELOPE_SIGNATURE_WITNESS=PASS
SIGNED_DENY_WITNESS=PASS
ADA_AUTHORIZATION_V2_WITNESSES=PASS
RESULT=3/3
ERRORS=NONE
```
