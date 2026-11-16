param(
    [Parameter(Mandatory)]
    [string]$RunRoot
)

$ErrorActionPreference = 'Stop'

$TRs =
    Split-Path -Parent $PSScriptRoot

$Matrix =
    Split-Path -Parent $TRs

$TestRoot =
    Split-Path -Parent $Matrix

$RepoRoot =
    Split-Path -Parent $TestRoot

$Evidence =
    Join-Path $RunRoot 'evidence'

$AdaCore =
    Get-Content `
        -LiteralPath (Join-Path $Evidence 'ada_core.log') `
        -Raw `
        -Encoding UTF8

$RustCore =
    Get-Content `
        -LiteralPath (Join-Path $Evidence 'rust_core.log') `
        -Raw `
        -Encoding UTF8

$AdaAuth =
    Get-Content `
        -LiteralPath (Join-Path $Evidence 'ada_authorization_v2.log') `
        -Raw `
        -Encoding UTF8

$RustAuth =
    Get-Content `
        -LiteralPath (Join-Path $Evidence 'rust_authorization_v2.log') `
        -Raw `
        -Encoding UTF8

Write-Host '=== t_rs 04 — RECONCILIATION ==='

# ------------------------------------------------------------
# Current direct Core
# ------------------------------------------------------------

if ($AdaCore -notmatch 'CORE_CANONICAL_CONFORMANCE=38/38 PASS') {
    throw 'Ada Core 38/38 evidence missing.'
}

if ($RustCore -notmatch 'RESULTS:\s+38/38 passed') {
    throw 'Rust Core 38/38 direct evidence missing.'
}

# ------------------------------------------------------------
# Authorization-v2
# ------------------------------------------------------------

foreach ($Pattern in @(
    'ACTION_HASH_WITNESS=PASS',
    'ENVELOPE_SIGNATURE_WITNESS=PASS',
    'SIGNED_DENY_WITNESS=PASS',
    'ADA_AUTHORIZATION_V2_WITNESSES=PASS',
    'RESULT=3/3',
    'ERRORS=NONE'
)) {
    if ($AdaAuth -notmatch [regex]::Escape($Pattern)) {
        throw "Ada Authorization-v2 evidence missing: $Pattern"
    }
}

foreach ($Pattern in @(
    'ACTION_HASH_WITNESS=PASS',
    'ENVELOPE_SIGNATURE_WITNESS=PASS',
    'SIGNED_DENY_WITNESS=PASS'
)) {
    if ($RustAuth -notmatch [regex]::Escape($Pattern)) {
        throw "Rust Authorization-v2 evidence missing: $Pattern"
    }
}

# ------------------------------------------------------------
# Historical 36+2 preservation
#
# Historical Rust accounting:
#   36 direct + 2 adjudicated / 38
#
# The two adjudicated cases remain named explicitly.
# Current Core-compatible Rust now passes both directly.
# Historical accounting is therefore preserved, not rewritten.
# ------------------------------------------------------------

$HistoricalCases = [ordered]@{
    'CORE-INV1-002' =
        Join-Path `
            $RepoRoot `
            'vectors\core\core_inv1_002_negative.json'

    'CORE-RUNTIME-004' =
        Join-Path `
            $RepoRoot `
            'vectors\core\runtime_004_negative.json'
}

foreach ($Entry in $HistoricalCases.GetEnumerator()) {

    $Vector =
        Get-Content `
            -LiteralPath $Entry.Value `
            -Raw `
            -Encoding UTF8 |
        ConvertFrom-Json

    $Expected =
        [string]$Vector.expected.outcome

    switch ($Entry.Key) {
        'CORE-INV1-002' {
            if ($Expected -ne 'CHECKPOINT') {
                throw (
                    'Historical case CORE-INV1-002 canonical ' +
                    "expected outcome changed: $Expected"
                )
            }
        }

        'CORE-RUNTIME-004' {
            if ($Expected -ne 'CHECKPOINT') {
                throw (
                    'Historical case CORE-RUNTIME-004 canonical ' +
                    "expected outcome changed: $Expected"
                )
            }
        }
    }

    if ($RustCore -notmatch (
        '\[PASS\]\s+' +
        [regex]::Escape($Entry.Key)
    )) {
        throw (
            "Current Rust direct PASS missing for $($Entry.Key)"
        )
    }

    if ($AdaCore -notmatch (
        '\[PASS\]\s+' +
        [regex]::Escape($Entry.Key)
    )) {
        throw (
            "Current Ada direct PASS missing for $($Entry.Key)"
        )
    }

    $HistoricalLine =
        (
            'HISTORICAL_ADJUDICATED_CASE={0} | ' +
            'CANONICAL_EXPECTED={1} | ' +
            'CURRENT_ADA=DIRECT_PASS | ' +
            'CURRENT_RUST=DIRECT_PASS'
        ) -f `
            $Entry.Key,
            $Expected

    Write-Host $HistoricalLine
}

# ------------------------------------------------------------
# Cross-implementation reconciliation
# ------------------------------------------------------------

Write-Host
Write-Host '=== CURRENT EVIDENCE ==='
Write-Host 'ADA_CORE_DIRECT=38/38'
Write-Host 'RUST_CORE_COMPATIBLE=38/38_DIRECT'
Write-Host 'ADA_AUTHORIZATION_V2=3/3'
Write-Host 'RUST_AUTHORIZATION_V2=3/3'

Write-Host
Write-Host '=== HISTORICAL ACCOUNTING ==='
Write-Host 'RUST_HISTORICAL_CORE=36_DIRECT_PLUS_2_ADJUDICATED/38'
Write-Host 'HISTORICAL_ADJUDICATED_1=CORE-INV1-002'
Write-Host 'HISTORICAL_ADJUDICATED_2=CORE-RUNTIME-004'
Write-Host 'HISTORICAL_RECORD_REWRITTEN=NO'

Write-Host
Write-Host '=== CROSS-IMPLEMENTATION ==='
Write-Host 'CROSS_IMPLEMENTATION_CORE=PASS'
Write-Host 'CROSS_IMPLEMENTATION_AUTHORIZATION_V2=PASS'
Write-Host 'KNOWN_SEMANTIC_RED=NONE'
Write-Host 'SYNTHETIC_TOTAL=NOT_USED'

$Summary = [ordered]@{
    release = '1.1.1'

    ada_core_direct =
        '38/38 PASS'

    rust_core_compatible =
        '38/38 DIRECT PASS'

    rust_historical_core =
        '36 DIRECT + 2 ADJUDICATED / 38'

    historical_adjudicated_cases = @(
        'CORE-INV1-002',
        'CORE-RUNTIME-004'
    )

    ada_authorization_v2 =
        '3/3 PASS'

    rust_authorization_v2 =
        '3/3 PASS'

    cross_implementation_core =
        'PASS'

    cross_implementation_authorization_v2 =
        'PASS'

    synthetic_total =
        'NOT_USED'

    known_semantic_red =
        'NONE'
}

$Summary |
    ConvertTo-Json -Depth 8 |
    Set-Content `
        -LiteralPath (
            Join-Path $RunRoot 'reconciliation.json'
        ) `
        -Encoding UTF8

Write-Host 'T_RS_RECONCILIATION=PASS'
