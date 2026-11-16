function Enable-TRsAdaRuntimeEnvironment {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = 'Stop'

    $ToolchainRoot =
        Join-Path `
            $env:LOCALAPPDATA `
            'alire\cache\toolchains'

    $MsysRoot =
        Join-Path `
            $env:LOCALAPPDATA `
            'alire\cache\msys64'

    if (-not (Test-Path -LiteralPath $ToolchainRoot -PathType Container)) {
        throw "Alire toolchain cache missing: $ToolchainRoot"
    }

    if (-not (Test-Path -LiteralPath $MsysRoot -PathType Container)) {
        throw "Alire MSYS2 cache missing: $MsysRoot"
    }

    $GnatRoots =
        @(
            Get-ChildItem `
                -LiteralPath $ToolchainRoot `
                -Directory |
            Where-Object {
                $_.Name -like 'gnat_native_14.2.1_*'
            }
        )

    if ($GnatRoots.Count -ne 1) {
        throw "GNAT 14.2.1 resolution count=$($GnatRoots.Count)"
    }

    $GprRoots =
        @(
            Get-ChildItem `
                -LiteralPath $ToolchainRoot `
                -Directory |
            Where-Object {
                $_.Name -like 'gprbuild_22.0.1_*'
            }
        )

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

    $SodiumDll =
        Join-Path $MingwBin 'libsodium-26.dll'

    foreach ($Required in @(
        $GnatBin,
        $GprBin,
        $MingwBin,
        $MingwLib,
        $SodiumDll
    )) {
        if (-not (Test-Path -LiteralPath $Required)) {
            throw "Ada runtime dependency missing: $Required"
        }
    }

    $Saved = [ordered]@{
        Path =
            $env:Path

        LibraryPathExists =
            Test-Path Env:\LIBRARY_PATH

        LibraryPath =
            $env:LIBRARY_PATH
    }

    $env:Path =
        "$GnatBin;$GprBin;$MingwBin;$env:Path"

    $env:LIBRARY_PATH =
        $MingwLib

    Write-Host '=== t_rs ADA RUNTIME ENVIRONMENT ==='
    Write-Host "GNAT_BIN=$GnatBin"
    Write-Host "GPRBUILD_BIN=$GprBin"
    Write-Host "MINGW_BIN=$MingwBin"
    Write-Host "MINGW_LIB=$MingwLib"
    Write-Host 'LIBSODIUM_RUNTIME=PASS'
    Write-Host 'ADA_RUNTIME_ENVIRONMENT=PASS'

    return [pscustomobject]$Saved
}

function Restore-TRsAdaRuntimeEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Saved
    )

    $env:Path =
        [string]$Saved.Path

    if ([bool]$Saved.LibraryPathExists) {
        $env:LIBRARY_PATH =
            [string]$Saved.LibraryPath
    }
    else {
        Remove-Item `
            Env:\LIBRARY_PATH `
            -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember `
    -Function `
        Enable-TRsAdaRuntimeEnvironment,
        Restore-TRsAdaRuntimeEnvironment
