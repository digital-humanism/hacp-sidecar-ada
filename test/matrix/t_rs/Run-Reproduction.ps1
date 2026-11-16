[CmdletBinding()]
param(
    [string]$RunRoot
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$TRs =
    $PSScriptRoot

$Scripts =
    Join-Path $TRs 'Scripts'

$Matrix =
    Split-Path -Parent $TRs

$TestRoot =
    Split-Path -Parent $Matrix

$RepoRoot =
    Split-Path -Parent $TestRoot

Write-Host '============================================================'
Write-Host 'HACP 1.1.1 — ADA / RUST CROSS-IMPLEMENTATION REPRODUCTION'
Write-Host '============================================================'
Write-Host

if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
    Write-Host 'Repository Git state: initialized'
}
else {
    Write-Host 'Repository Git state: not initialized'
}

# ------------------------------------------------------------
# A caller may provide a RunRoot for controlled automation.
# Ordinary public reproduction gets a fresh unique temp root.
# ------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($RunRoot)) {

    $RunId =
        [guid]::NewGuid().ToString()

    $RunRoot =
        Join-Path `
            ([System.IO.Path]::GetTempPath()) `
            (
                'hacp-sidecar-ada-t_rs-1.1.1-' +
                $RunId
            )
}
else {
    $RunRoot =
        [System.IO.Path]::GetFullPath($RunRoot)
}

Write-Host "RUN_ROOT=$RunRoot"
Write-Host

$Phases = @(
    '00-Preflight.ps1',
    '01-Prepare-Environment.ps1',
    '02-Run-Verification.ps1',
    '03-Postflight.ps1',
    '04-Reconcile-Results.ps1',
    '05-Generate-Report.ps1'
)

foreach ($Phase in $Phases) {

    $Path =
        Join-Path $Scripts $Phase

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required reproduction phase missing: $Path"
    }
}

$StartedAt =
    Get-Date

foreach ($Phase in $Phases) {

    $Path =
        Join-Path $Scripts $Phase

    Write-Host
    Write-Host '------------------------------------------------------------'
    Write-Host "EXECUTE: $Phase"
    Write-Host '------------------------------------------------------------'

    & pwsh `
        -NoProfile `
        -File $Path `
        -RunRoot $RunRoot

    $Rc =
        $LASTEXITCODE

    Write-Host "$Phase RC=$Rc"

    if ($Rc -ne 0) {

        Write-Host
        Write-Host '============================================================'
        Write-Host 'REPRODUCTION RESULT: RED'
        Write-Host '============================================================'
        Write-Host "FAILED_PHASE=$Phase"
        Write-Host "EXIT_CODE=$Rc"
        Write-Host "RUN_ROOT=$RunRoot"

        throw "Reproduction stopped at $Phase with RC=$Rc"
    }
}

$EndedAt =
    Get-Date

$Elapsed =
    $EndedAt - $StartedAt

$ReportRoot =
    Join-Path $RunRoot 'report'

$ReportMd =
    Join-Path `
        $ReportRoot `
        'HACP_SIDECAR_ADA_RUST_CROSS_IMPLEMENTATION_REPRODUCTION.md'

$ReportHtml =
    Join-Path `
        $ReportRoot `
        'HACP_SIDECAR_ADA_RUST_CROSS_IMPLEMENTATION_REPRODUCTION.html'

$Reconciliation =
    Join-Path $RunRoot 'reconciliation.json'

foreach ($Path in @(
    $ReportMd,
    $ReportHtml,
    $Reconciliation
)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected final artifact missing: $Path"
    }
}

$R =
    Get-Content `
        -LiteralPath $Reconciliation `
        -Raw `
        -Encoding UTF8 |
    ConvertFrom-Json

if ($null -eq $R) {
    throw 'Final reconciliation artifact is invalid.'
}

if (
    [string]$R.ada_core_direct -ne '38/38 PASS' -or
    [string]$R.rust_core_compatible -ne '38/38 DIRECT PASS' -or
    [string]$R.ada_authorization_v2 -ne '3/3 PASS' -or
    [string]$R.rust_authorization_v2 -ne '3/3 PASS' -or
    [string]$R.cross_implementation_core -ne 'PASS' -or
    [string]$R.cross_implementation_authorization_v2 -ne 'PASS' -or
    [string]$R.known_semantic_red -ne 'NONE' -or
    [string]$R.synthetic_total -ne 'NOT_USED'
) {
    throw 'Final reconciliation contract is not PASS.'
}

Write-Host
Write-Host '============================================================'
Write-Host 'REPRODUCTION RESULT: PASS'
Write-Host '============================================================'
Write-Host
Write-Host 'ADA_CORE=38/38 PASS'
Write-Host 'RUST_CORE=38/38 DIRECT PASS'
Write-Host 'ADA_AUTHORIZATION_V2=3/3 PASS'
Write-Host 'RUST_AUTHORIZATION_V2=3/3 PASS'
Write-Host 'CROSS_IMPLEMENTATION_CORE=PASS'
Write-Host 'CROSS_IMPLEMENTATION_AUTHORIZATION_V2=PASS'
Write-Host 'KNOWN_SEMANTIC_RED=NONE'
Write-Host 'SYNTHETIC_TOTAL=NOT_USED'
Write-Host
Write-Host (
    'ELAPSED=' +
    $Elapsed.ToString()
)
Write-Host
Write-Host "RUN_ROOT=$RunRoot"
Write-Host "REPORT_MD=$ReportMd"
Write-Host "REPORT_HTML=$ReportHtml"
Write-Host
Write-Host 'Open REPORT_HTML in a browser to inspect the reproduction report.'
