$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$TAda =
    Split-Path -Parent $PSScriptRoot

$Matrix =
    Split-Path -Parent $TAda

$TestRoot =
    Split-Path -Parent $Matrix

$RepoRoot =
    Split-Path -Parent $TestRoot

$Observer =
    Join-Path $TAda 'Observers\ada-core38-final-observer.py'

$HarnessDir =
    Join-Path $RepoRoot 'harness'

$Manifest =
    Join-Path $HarnessDir 'conformance_manifest.json'

$Vectors =
    Join-Path $RepoRoot 'vectors\core'

$Runner =
    Join-Path $RepoRoot 'bin\hacp_ada_runner.exe'

foreach ($Required in @(
    $Observer,
    $HarnessDir,
    $Manifest,
    $Vectors,
    $Runner
)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        throw "Missing required Core input: $Required"
    }
}

$VectorCount =
    @(
        Get-ChildItem `
            -LiteralPath $Vectors `
            -File `
            -Filter '*.json'
    ).Count

if ($VectorCount -ne 38) {
    throw "Unexpected Core vector count: $VectorCount"
}

Write-Host '=== HACP SIDECAR ADA — CORE 38 ==='
Write-Host "HARNESS_DIR=$HarnessDir"
Write-Host "MANIFEST=$Manifest"
Write-Host "VECTORS=$Vectors"
Write-Host "CORE_JSON_COUNT=$VectorCount"
Write-Host "RUNNER=$Runner"

python `
    $Observer `
    --harness-dir $HarnessDir `
    --vectors $Vectors `
    --manifest $Manifest `
    --runner $Runner

$ExitCode = $LASTEXITCODE

Write-Host "CORE_EXIT_CODE=$ExitCode"

if ($ExitCode -ne 0) {
    throw "Core verification failed with exit code $ExitCode"
}

Write-Host 'ADA_CORE=PASS'
