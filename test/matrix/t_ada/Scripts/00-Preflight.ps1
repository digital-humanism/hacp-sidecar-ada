$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ($PSVersionTable.PSEdition -ne 'Core') {
    throw (
        'HACP Ada reproduction requires PowerShell Core. ' +
        "Observed PSEdition=$($PSVersionTable.PSEdition)"
    )
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw (
        'HACP Ada reproduction requires PowerShell 7 or newer. ' +
        "Observed version=$($PSVersionTable.PSVersion)"
    )
}

if (-not [Environment]::Is64BitProcess) {
    throw 'HACP Ada reproduction requires a 64-bit PowerShell process.'
}

$TAda =
    Split-Path -Parent $PSScriptRoot

$Matrix =
    Split-Path -Parent $TAda

$TestRoot =
    Split-Path -Parent $Matrix

$RepoRoot =
    Split-Path -Parent $TestRoot

$RequiredRepoFiles = @(
    'alire.toml',
    'hacp_ada.gpr',
    'harness\conformance_manifest.json',
    'harness\requirements.txt',
    'harness\keys\KEYS.md',
    'harness\keys\test-ed25519-001.pub',
    'harness\keys\test-ed25519-001.seed'
)

foreach ($Rel in $RequiredRepoFiles) {
    $Path = Join-Path $RepoRoot $Rel

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required repository input missing: $Rel"
    }
}

$CoreVectors =
    @(
        Get-ChildItem `
            -LiteralPath (Join-Path $RepoRoot 'vectors\core') `
            -File `
            -Filter '*.json'
    ).Count

$HC2Vectors =
    @(
        Get-ChildItem `
            -LiteralPath (Join-Path $RepoRoot 'vectors\enforcement-v2') `
            -File `
            -Filter '*.json'
    ).Count

if ($CoreVectors -ne 38) {
    throw "Expected 38 Core vectors, observed $CoreVectors"
}

if ($HC2Vectors -ne 55) {
    throw "Expected 55 HC2 vectors, observed $HC2Vectors"
}

$RequiredCommands = @(
    'python',
    'go',
    'alr'
)

foreach ($Name in $RequiredCommands) {
    if ($null -eq (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not available on PATH: $Name"
    }
}

Write-Host '=== PUBLIC MATRIX PREFLIGHT ==='
Write-Host "REPO_ROOT=$RepoRoot"
Write-Host "PSEDITION=$($PSVersionTable.PSEdition)"
Write-Host "PSVERSION=$($PSVersionTable.PSVersion)"
Write-Host "PROCESS_64BIT=$([Environment]::Is64BitProcess)"
Write-Host "CORE_VECTOR_COUNT=$CoreVectors"
Write-Host "HC2_VECTOR_COUNT=$HC2Vectors"

Write-Host '=== ALIRE-OWNED ADA TOOLCHAIN ==='

& alr --version

if ($LASTEXITCODE -ne 0) {
    throw 'Alire version check failed.'
}

& alr toolchain

if ($LASTEXITCODE -ne 0) {
    throw 'Alire toolchain query failed.'
}

& alr exec -- gnatmake --version |
    Select-Object -First 1

if ($LASTEXITCODE -ne 0) {
    throw 'Alire-owned gnatmake check failed.'
}

& alr exec -- gcc -dumpmachine

if ($LASTEXITCODE -ne 0) {
    throw 'Alire-owned gcc target check failed.'
}

& alr exec -- gcc -dumpversion

if ($LASTEXITCODE -ne 0) {
    throw 'Alire-owned gcc version check failed.'
}

& alr exec -- gprbuild --version |
    Select-Object -First 1

if ($LASTEXITCODE -ne 0) {
    throw 'Alire-owned gprbuild check failed.'
}

Write-Host 'PREFLIGHT_BUILD=NOT_RUN'
Write-Host 'PREFLIGHT_TESTS=NOT_RUN'
Write-Host 'PREFLIGHT_RUNTIME=NOT_RUN'
Write-Host 'ADA_PUBLIC_PREFLIGHT=PASS'
