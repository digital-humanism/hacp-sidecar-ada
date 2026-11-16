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

$Evidence =
    Join-Path $RunRoot 'evidence'

$CargoTarget =
    Join-Path $RunRoot 'work\cargo-target'

Write-Host '=== t_rs 01 — PREPARE ENVIRONMENT ==='

# ------------------------------------------------------------
# Ada: reuse existing repository-owned preparation unchanged.
# This performs a fresh build; no previous verdict is reused.
# ------------------------------------------------------------

$AdaPrepare =
    Join-Path $TAda 'Scripts\01-Prepare-Environment.ps1'

$AdaPrepareLog =
    Join-Path $Evidence 'ada_prepare.log'

$AdaPrepareOutput =
    @(
        & pwsh `
            -NoProfile `
            -File $AdaPrepare 2>&1
    )

$AdaPrepareRc =
    $LASTEXITCODE

$AdaPrepareOutput |
    Set-Content `
        -LiteralPath $AdaPrepareLog `
        -Encoding UTF8

$AdaPrepareOutput |
    ForEach-Object {
        Write-Host $_
    }

if ($AdaPrepareRc -ne 0) {
    throw "Ada preparation failed: RC=$AdaPrepareRc"
}

foreach ($Runner in @(
    (Join-Path $RepoRoot 'bin\hacp_ada_runner.exe'),
    (Join-Path $RepoRoot 'bin\hacp_ada_auth_v2_runner.exe')
)) {
    if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
        throw "Ada runner missing after preparation: $Runner"
    }
}

Write-Host 'ADA_PREPARATION=PASS'

# ------------------------------------------------------------
# Rust: repository-owned bounded package only.
# Cargo.lock is now authoritative for this reproduction.
# ------------------------------------------------------------

Push-Location $Rust

try {
    $env:CARGO_TARGET_DIR =
        $CargoTarget

    & cargo `
        +stable-x86_64-pc-windows-msvc `
        build `
        --locked `
        --release `
        --bin hacp-rs-core-runner

    $CoreRc =
        $LASTEXITCODE

    if ($CoreRc -ne 0) {
        throw "Rust Core runner build failed: RC=$CoreRc"
    }

    & cargo `
        +stable-x86_64-pc-windows-msvc `
        build `
        --locked `
        --release `
        --bin hacp-rs-runner

    $AuthRc =
        $LASTEXITCODE

    if ($AuthRc -ne 0) {
        throw "Rust Authorization-v2 runner build failed: RC=$AuthRc"
    }
}
finally {
    Pop-Location
    Remove-Item Env:\CARGO_TARGET_DIR -ErrorAction SilentlyContinue
}

$RustCore =
    Join-Path $CargoTarget 'release\hacp-rs-core-runner.exe'

$RustAuth =
    Join-Path $CargoTarget 'release\hacp-rs-runner.exe'

foreach ($Runner in @(
    $RustCore,
    $RustAuth
)) {
    if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
        throw "Rust runner missing after build: $Runner"
    }
}

$Context = [ordered]@{
    run_root = $RunRoot
    rust_core_runner = $RustCore
    rust_authorization_v2_runner = $RustAuth
}

$Context |
    ConvertTo-Json -Depth 8 |
    Set-Content `
        -LiteralPath (Join-Path $RunRoot 'run-context.json') `
        -Encoding UTF8

Write-Host 'RUST_BUILD_MODE=LOCKED'
Write-Host 'RUST_CORE_RUNNER_BUILD=PASS'
Write-Host 'RUST_AUTH_V2_RUNNER_BUILD=PASS'
Write-Host 'T_RS_PREPARE=PASS'
