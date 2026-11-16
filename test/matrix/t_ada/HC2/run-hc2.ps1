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
    Join-Path $TAda 'Observers\ada-hc2-55-final-observer.py'

$HarnessDir =
    Join-Path $RepoRoot 'harness'

$Vectors =
    Join-Path $RepoRoot 'vectors\enforcement-v2'

$Runner =
    Join-Path $RepoRoot 'bin\hacp_ada_runner.exe'

foreach ($Required in @(
    $Observer,
    $HarnessDir,
    $Vectors,
    $Runner
)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        throw "Missing required HC2 input: $Required"
    }
}

$VectorCount =
    @(
        Get-ChildItem `
            -LiteralPath $Vectors `
            -File `
            -Filter '*.json'
    ).Count

if ($VectorCount -ne 55) {
    throw "Unexpected HC2 vector count: $VectorCount"
}

Write-Host '=== HACP SIDECAR ADA — HC2-55 ==='
Write-Host "HARNESS_DIR=$HarnessDir"
Write-Host "VECTORS=$Vectors"
Write-Host "HC2_JSON_COUNT=$VectorCount"
Write-Host "RUNNER=$Runner"

python `
    $Observer `
    --harness-dir $HarnessDir `
    --vectors $Vectors `
    --runner $Runner

$ExitCode = $LASTEXITCODE

Write-Host "HC2_EXIT_CODE=$ExitCode"

if ($ExitCode -ne 0) {
    throw "HC2 verification failed with exit code $ExitCode"
}

Write-Host 'ADA_HC2=PASS'
