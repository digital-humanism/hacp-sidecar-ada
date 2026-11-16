param(
    [Parameter(Mandatory)]
    [string]$RunRoot
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$TRs =
    Split-Path -Parent $PSScriptRoot

$Matrix =
    Split-Path -Parent $TRs

$TestRoot =
    Split-Path -Parent $Matrix

$RepoRoot =
    Split-Path -Parent $TestRoot

$TAda =
    Join-Path $Matrix 't_ada'

$Evidence =
    Join-Path $RunRoot 'evidence'

$ContextPath =
    Join-Path $RunRoot 'run-context.json'

if (-not (Test-Path -LiteralPath $ContextPath -PathType Leaf)) {
    throw "Run context missing: $ContextPath"
}

$Context =
    Get-Content `
        -LiteralPath $ContextPath `
        -Raw `
        -Encoding UTF8 |
    ConvertFrom-Json

$RustCore =
    [string]$Context.rust_core_runner

$RustAuth =
    [string]$Context.rust_authorization_v2_runner

foreach ($Runner in @(
    $RustCore,
    $RustAuth
)) {
    if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
        throw "Prepared Rust runner missing: $Runner"
    }
}

$Harness =
    Join-Path $RepoRoot 'harness\harness_runner.py'

$Manifest =
    Join-Path $RepoRoot 'harness\conformance_manifest.json'

$Vectors =
    Join-Path $RepoRoot 'vectors\core'

Write-Host '=== t_rs 02 — FRESH VERIFICATION ==='

Import-Module `
    (Join-Path $PSScriptRoot 'AdaRuntimeEnvironment.psm1') `
    -Force

$AdaRuntimeEnvironment =
    Enable-TRsAdaRuntimeEnvironment

try {

# ============================================================
# FAMILY 1 — ADA CORE
# Fresh execution of repository-owned Ada runner.
# ============================================================

Write-Host
Write-Host '=== FAMILY: ADA CORE ==='

$AdaCoreScript =
    Join-Path $TAda 'Core\run-core.ps1'

$AdaCoreOutput =
    @(
        & pwsh `
            -NoProfile `
            -File $AdaCoreScript 2>&1
    )

$AdaCoreRc =
    $LASTEXITCODE

$AdaCoreOutput |
    Set-Content `
        -LiteralPath (Join-Path $Evidence 'ada_core.log') `
        -Encoding UTF8

$AdaCoreOutput |
    ForEach-Object {
        Write-Host $_
    }

if ($AdaCoreRc -ne 0) {
    throw "Ada Core execution failed: RC=$AdaCoreRc"
}

if (-not ($AdaCoreOutput -contains 'ADA_CORE=PASS')) {
    throw 'Ada Core PASS marker missing.'
}

Write-Host 'FAMILY_ADA_CORE=PASS'

# ============================================================
# FAMILY 2 — RUST CORE
# Same root vectors + same root manifest.
# ============================================================

Write-Host
Write-Host '=== FAMILY: RUST CORE ==='

$RustCoreOutput =
    @(
        python `
            $Harness `
            --runner $RustCore `
            --manifest $Manifest `
            --vectors-dir $Vectors `
            --implementation-name 'hacp-rs-core' `
            --implementation-version '0.1.1' 2>&1
    )

$RustCoreRc =
    $LASTEXITCODE

$RustCoreOutput |
    Set-Content `
        -LiteralPath (Join-Path $Evidence 'rust_core.log') `
        -Encoding UTF8

$RustCoreOutput |
    ForEach-Object {
        Write-Host $_
    }

if ($RustCoreRc -ne 0) {
    throw "Rust Core execution failed: RC=$RustCoreRc"
}

if (-not (
    $RustCoreOutput |
        Select-String `
            -SimpleMatch `
            -Pattern 'RESULTS: 38/38 passed'
)) {
    throw 'Rust Core did not report 38/38 passed.'
}

Write-Host 'RUST_CORE_COMPATIBLE=38/38_DIRECT_PASS'
Write-Host 'FAMILY_RUST_CORE=PASS'

# ============================================================
# FAMILY 3 — ADA AUTHORIZATION-v2
# Fresh execution; existing script generates fresh witnesses.
# ============================================================

Write-Host
Write-Host '=== FAMILY: ADA AUTHORIZATION-V2 ==='

$AdaAuthScript =
    Join-Path $TAda 'AuthorizationV2\run-witnesses.ps1'

$AdaAuthOutput =
    @(
        & pwsh `
            -NoProfile `
            -File $AdaAuthScript 2>&1
    )

$AdaAuthRc =
    $LASTEXITCODE

$AdaAuthOutput |
    Set-Content `
        -LiteralPath (Join-Path $Evidence 'ada_authorization_v2.log') `
        -Encoding UTF8

$AdaAuthOutput |
    ForEach-Object {
        Write-Host $_
    }

if ($AdaAuthRc -ne 0) {
    throw "Ada Authorization-v2 failed: RC=$AdaAuthRc"
}

foreach ($Expected in @(
    'ACTION_HASH_WITNESS=PASS',
    'ENVELOPE_SIGNATURE_WITNESS=PASS',
    'SIGNED_DENY_WITNESS=PASS',
    'ADA_AUTHORIZATION_V2_WITNESSES=PASS',
    'RESULT=3/3',
    'ERRORS=NONE'
)) {
    if (-not ($AdaAuthOutput -contains $Expected)) {
        throw "Ada Authorization-v2 marker missing: $Expected"
    }
}

Write-Host 'FAMILY_ADA_AUTHORIZATION_V2=PASS'

# ============================================================
# FAMILY 4 — RUST AUTHORIZATION-v2
#
# Generate the same semantic witness set using the existing
# repository-owned generator, then send witness.input and
# witness.policy_context through the Rust Protocol v1 runner.
# ============================================================

Write-Host
Write-Host '=== FAMILY: RUST AUTHORIZATION-V2 ==='

$Generator =
    Join-Path $TAda 'AuthorizationV2\generate_witnesses.py'

$WitnessRoot =
    Join-Path $RunRoot 'witnesses'

if (Test-Path -LiteralPath $WitnessRoot) {
    Remove-Item `
        -LiteralPath $WitnessRoot `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $WitnessRoot |
Out-Null

$GeneratorOutput =
    @(
        python `
            $Generator `
            --out $WitnessRoot 2>&1
    )

$GeneratorRc =
    $LASTEXITCODE

if ($GeneratorRc -ne 0) {
    throw "Witness generation failed: RC=$GeneratorRc"
}

if (-not ($GeneratorOutput -contains 'AUTH_V2_WITNESS_GENERATION=PASS')) {
    throw 'Witness generation PASS marker missing.'
}

function Invoke-RustWitness {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$File,

        [Parameter(Mandatory)]
        [string]$ExpectedDecision,

        [Parameter(Mandatory)]
        [string]$ExpectedReason
    )

    $Witness =
        Get-Content `
            -LiteralPath $File `
            -Raw `
            -Encoding UTF8 |
        ConvertFrom-Json

    $Request =
        [ordered]@{
            protocol_version = '1'
            operation        = 'evaluate'
            vector_id        = $Name
            input            = $Witness.input
            policy_context   = $Witness.policy_context
        } |
        ConvertTo-Json `
            -Depth 100 `
            -Compress

    $Output =
        @(
            $Request |
                & $RustAuth
        )

    $Rc =
        if ($null -eq $LASTEXITCODE) {
            0
        }
        else {
            $LASTEXITCODE
        }

    if ($Rc -ne 0) {
        throw "$Name Rust runner exit code $Rc"
    }

    if ($Output.Count -lt 1) {
        throw "$Name Rust runner returned no response"
    }

    $Response =
        $Output[-1] |
        ConvertFrom-Json

    $Decision =
        [string]$Response.decision

    $Reasons =
        @(
            $Response.reason_codes |
                ForEach-Object {
                    [string]$_
                }
        )

    if ($Decision -ne $ExpectedDecision) {
        throw (
            "$Name expected decision $ExpectedDecision, " +
            "observed $Decision"
        )
    }

    if ($Reasons -notcontains $ExpectedReason) {
        throw (
            "$Name expected reason $ExpectedReason, " +
            "observed: $($Reasons -join ',')"
        )
    }

    $Line =
        "$Name=PASS | DECISION=$Decision | REASON=$ExpectedReason"

    Write-Host $Line
    return $Line
}

$RustWitnessResults =
    @()

$RustWitnessResults +=
    Invoke-RustWitness `
        -Name 'ACTION_HASH_WITNESS' `
        -File (Join-Path $WitnessRoot 'action_hash_witness.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'SIGNATURE_FAILURE'

$RustWitnessResults +=
    Invoke-RustWitness `
        -Name 'ENVELOPE_SIGNATURE_WITNESS' `
        -File (Join-Path $WitnessRoot 'envelope_signature_witness.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'SIGNATURE_FAILURE'

$RustWitnessResults +=
    Invoke-RustWitness `
        -Name 'SIGNED_DENY_WITNESS' `
        -File (Join-Path $WitnessRoot 'signed_deny_witness.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'POLICY_DENIED'

$RustWitnessResults |
    Set-Content `
        -LiteralPath (Join-Path $Evidence 'rust_authorization_v2.log') `
        -Encoding UTF8

Write-Host 'RUST_AUTHORIZATION_V2_WITNESSES=PASS'
Write-Host 'RESULT=3/3'
Write-Host 'ERRORS=NONE'
Write-Host 'FAMILY_RUST_AUTHORIZATION_V2=PASS'

}
finally {
    Restore-TRsAdaRuntimeEnvironment `
        -Saved $AdaRuntimeEnvironment
}

# ============================================================
# FRESH EXECUTION SUMMARY
# ============================================================

Write-Host
Write-Host '=== t_rs FRESH EXECUTION SUMMARY ==='
Write-Host 'ADA_CORE=38/38_PASS'
Write-Host 'RUST_CORE=38/38_DIRECT_PASS'
Write-Host 'ADA_AUTHORIZATION_V2=3/3_PASS'
Write-Host 'RUST_AUTHORIZATION_V2=3/3_PASS'
Write-Host 'SYNTHETIC_TOTAL=NOT_USED'
Write-Host 'KNOWN_SEMANTIC_RED=NONE'
Write-Host 'T_RS_FRESH_EXECUTION=PASS'
