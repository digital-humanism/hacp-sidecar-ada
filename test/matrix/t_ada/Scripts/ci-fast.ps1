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

Write-Host '============================================================'
Write-Host 'HACP SIDECAR ADA — FAST CI'
Write-Host '============================================================'

if ($PSVersionTable.PSEdition -ne 'Core') {
    throw 'Fast CI requires PowerShell Core.'
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Fast CI requires PowerShell 7 or newer.'
}

if (-not [Environment]::Is64BitProcess) {
    throw 'Fast CI requires 64-bit PowerShell.'
}

foreach ($Name in @(
    'python',
    'alr'
)) {
    if ($null -eq (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not available: $Name"
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

Write-Host "CORE_VECTOR_COUNT=$CoreVectors"
Write-Host "HC2_VECTOR_COUNT=$HC2Vectors"

Write-Host
Write-Host '=== TOOLCHAIN ==='

& alr --version

if ($LASTEXITCODE -ne 0) {
    throw 'Alire version check failed.'
}

& alr toolchain

if ($LASTEXITCODE -ne 0) {
    throw 'Alire toolchain query failed.'
}

$ToolchainRoot =
    Join-Path $env:LOCALAPPDATA 'alire\cache\toolchains'

$MsysRoot =
    if (
        -not [string]::IsNullOrWhiteSpace(
            $env:HACP_MSYS2_ROOT
        )
    ) {
        $env:HACP_MSYS2_ROOT
    }
    else {
        Join-Path `
            $env:LOCALAPPDATA `
            'alire\cache\msys64'
    }

$MsysSource =
    if (
        -not [string]::IsNullOrWhiteSpace(
            $env:HACP_MSYS2_ROOT
        )
    ) {
        'CI_EXPLICIT'
    }
    else {
        'ALIRE_LOCAL_FALLBACK'
    }

Write-Host "MSYS2_ROOT=$MsysRoot"
Write-Host "MSYS2_SOURCE=$MsysSource"

$GnatRoots =
    @(
        Get-ChildItem `
            -LiteralPath $ToolchainRoot `
            -Directory |
        Where-Object {
            $_.Name -like 'gnat_native_14.2.1_*'
        }
    )

$GprRoots =
    @(
        Get-ChildItem `
            -LiteralPath $ToolchainRoot `
            -Directory |
        Where-Object {
            $_.Name -like 'gprbuild_22.0.1_*'
        }
    )

if ($GnatRoots.Count -ne 1) {
    throw "GNAT 14.2.1 resolution count=$($GnatRoots.Count)"
}

if ($GprRoots.Count -ne 1) {
    throw "GPRBuild 22.0.1 resolution count=$($GprRoots.Count)"
}

$GnatBin =
    Join-Path $GnatRoots[0].FullName 'bin'

$GprBin =
    Join-Path $GprRoots[0].FullName 'bin'

$MingwBin =
    Join-Path $MsysRoot 'mingw64\bin'

$MingwLib =
    Join-Path $MsysRoot 'mingw64\lib'

foreach ($RuntimePath in @(
    $GnatBin,
    $GprBin,
    $MingwBin,
    $MingwLib
)) {
    if (-not (Test-Path -LiteralPath $RuntimePath -PathType Container)) {
        throw "Runtime directory missing: $RuntimePath"
    }
}

$SodiumDll =
    Join-Path $MingwBin 'libsodium-26.dll'

if (-not (Test-Path -LiteralPath $SodiumDll -PathType Leaf)) {
    throw "libsodium runtime missing: $SodiumDll"
}

$SodiumImportLibrary =
    Join-Path $MingwLib 'libsodium.dll.a'

$SodiumStaticLibrary =
    Join-Path $MingwLib 'libsodium.a'

if (
    -not (
        (Test-Path -LiteralPath $SodiumImportLibrary -PathType Leaf) -or
        (Test-Path -LiteralPath $SodiumStaticLibrary -PathType Leaf)
    )
) {
    throw "libsodium link library missing under: $MingwLib"
}

Write-Host "MINGW_LIB=$MingwLib"
Write-Host 'LIBSODIUM_LINK_MATERIAL=PASS'
Write-Host 'TOOLCHAIN_RESOLUTION=PASS'

Set-Location -LiteralPath $RepoRoot

foreach ($Dir in @(
    (Join-Path $RepoRoot 'bin'),
    (Join-Path $RepoRoot 'obj')
)) {
    if (Test-Path -LiteralPath $Dir) {
        Remove-Item `
            -LiteralPath $Dir `
            -Recurse `
            -Force
    }

    New-Item `
        -ItemType Directory `
        -Path $Dir |
        Out-Null
}

Write-Host
Write-Host '=== CLEAN BUILD ==='

$OriginalLibraryPath =
    $env:LIBRARY_PATH

try {
    $env:LIBRARY_PATH =
        if (
            [string]::IsNullOrWhiteSpace(
                $OriginalLibraryPath
            )
        ) {
            $MingwLib
        }
        else {
            "$MingwLib;$OriginalLibraryPath"
        }

    Write-Host "EXPLICIT_LINK_LIBRARY_PATH=$MingwLib"

    & alr build

    if ($LASTEXITCODE -ne 0) {
        throw "Ada build failed with exit code $LASTEXITCODE"
    }
}
finally {
    $env:LIBRARY_PATH =
        $OriginalLibraryPath
}

$ExpectedExecutables = @(
    'hacp_ada_auth_v2_runner.exe',
    'hacp_ada_controlplane.exe',
    'hacp_ada_integrated.exe',
    'hacp_ada_mcp.exe',
    'hacp_ada_proxy.exe',
    'hacp_ada_runner.exe'
)

$ActualExecutables =
    @(
        Get-ChildItem `
            -LiteralPath (Join-Path $RepoRoot 'bin') `
            -File `
            -Filter '*.exe' |
        Sort-Object Name |
        ForEach-Object Name
    )

$ExecutableDiff =
    @(
        Compare-Object `
            $ExpectedExecutables `
            $ActualExecutables
    )

if ($ExecutableDiff.Count -ne 0) {
    $ExecutableDiff | Format-Table -AutoSize
    throw 'Unexpected executable set.'
}

Write-Host 'ADA_BUILD=PASS'
Write-Host 'EXE_COUNT=6'

$OriginalPath =
    $env:Path

try {
    $env:Path =
        "$GnatBin;$GprBin;$MingwBin;$OriginalPath"

    $Families = @(
        @{
            Name = 'CORE'
            Path = Join-Path $TAda 'Core\run-core.ps1'
        },
        @{
            Name = 'HC2'
            Path = Join-Path $TAda 'HC2\run-hc2.ps1'
        },
        @{
            Name = 'AUTHORIZATION_V2'
            Path = Join-Path $TAda 'AuthorizationV2\run-witnesses.ps1'
        }
    )

    foreach ($Family in $Families) {
        Write-Host
        Write-Host "=== FAMILY: $($Family.Name) ==="

        & pwsh `
            -NoLogo `
            -NoProfile `
            -File $Family.Path

        if ($LASTEXITCODE -ne 0) {
            throw (
                "Family $($Family.Name) failed with exit code " +
                "$LASTEXITCODE"
            )
        }

        Write-Host "FAMILY_$($Family.Name)=PASS"
    }
}
finally {
    $env:Path =
        $OriginalPath
}

Write-Host
Write-Host '============================================================'
Write-Host 'FAST CI FINAL'
Write-Host '============================================================'
Write-Host 'ADA_BUILD=PASS'
Write-Host 'CORE_FAMILY=PASS'
Write-Host 'HC2_FAMILY=PASS'
Write-Host 'AUTHORIZATION_V2_FAMILY=PASS'
Write-Host 'GO_REQUIRED=NO'
Write-Host 'PARITY_RUN=NO'
Write-Host 'RUNTIME_RUN=NO'
Write-Host 'HTTP_RUN=NO'
Write-Host 'SYNTHETIC_TOTAL=NOT_USED'
Write-Host 'ADA_FAST_CI=PASS'
