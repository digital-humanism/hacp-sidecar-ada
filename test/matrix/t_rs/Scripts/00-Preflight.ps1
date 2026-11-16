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

$Rust =
    Join-Path $TRs 'rust'

Write-Host '=== t_rs 00 — PREFLIGHT ==='
Write-Host "REPO_ROOT=$RepoRoot"
Write-Host "RUN_ROOT=$RunRoot"

if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
    throw 'Git must not be initialized before P18.'
}

$Required = @(
    (Join-Path $RepoRoot 'alire.toml'),
    (Join-Path $RepoRoot 'hacp_ada.gpr'),
    (Join-Path $RepoRoot 'harness\harness_runner.py'),
    (Join-Path $RepoRoot 'harness\conformance_manifest.json'),
    (Join-Path $RepoRoot 'vectors\core'),
    (Join-Path $TAda 'Scripts\00-Preflight.ps1'),
    (Join-Path $TAda 'Scripts\01-Prepare-Environment.ps1'),
    (Join-Path $TAda 'Core\run-core.ps1'),
    (Join-Path $TAda 'AuthorizationV2\run-witnesses.ps1'),
    (Join-Path $TAda 'AuthorizationV2\generate_witnesses.py'),
    (Join-Path $Rust 'Cargo.toml'),
    (Join-Path $Rust 'Cargo.lock'),
    (Join-Path $Rust 'src\bin\hacp-rs-runner.rs'),
    (Join-Path $Rust 'src\bin\hacp-rs-core-runner.rs')
)

foreach ($Path in $Required) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required repository-owned asset missing: $Path"
    }
}

foreach ($Command in @(
    'pwsh',
    'python',
    'alr',
    'rustc',
    'cargo',
    'rustup'
)) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command unavailable: $Command"
    }
}

$Toolchains =
    @(& rustup toolchain list)

if ($LASTEXITCODE -ne 0) {
    throw 'rustup toolchain list failed.'
}

if (-not ($Toolchains -match 'stable-x86_64-pc-windows-msvc')) {
    throw 'Required Rust MSVC toolchain is not installed.'
}

$CoreCount =
    @(
        Get-ChildItem `
            -LiteralPath (Join-Path $RepoRoot 'vectors\core') `
            -File `
            -Filter '*.json'
    ).Count

if ($CoreCount -ne 38) {
    throw "Unexpected Core vector count: $CoreCount"
}

foreach ($Name in @(
    'core_inv1_001_golden.json',
    'core_inv1_002_negative.json',
    'runtime_004_negative.json'
)) {
    $Path =
        Join-Path (Join-Path $RepoRoot 'vectors\core') $Name

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required Core case missing: $Path"
    }
}

foreach ($Dir in @(
    $RunRoot,
    (Join-Path $RunRoot 'evidence'),
    (Join-Path $RunRoot 'work'),
    (Join-Path $RunRoot 'witnesses')
)) {
    if (-not (Test-Path -LiteralPath $Dir)) {
        New-Item `
            -ItemType Directory `
            -Path $Dir `
            -Force |
        Out-Null
    }
}

Write-Host "CORE_JSON_COUNT=$CoreCount"
Write-Host 'LAB_RUNTIME_DEPENDENCY=NONE'
Write-Host 'SIBLING_REPOSITORY_DEPENDENCY=NONE'
Write-Host 'SHA_SELECTOR=NONE'
Write-Host 'T_RS_PREFLIGHT=PASS'
