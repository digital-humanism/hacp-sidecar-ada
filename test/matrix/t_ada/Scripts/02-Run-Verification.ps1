$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Utf8NoBom =
    [System.Text.UTF8Encoding]::new($false)

function Write-Utf8Lf {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content
    )

    $Normalized =
        $Content -replace "`r`n", "`n"

    $Normalized =
        $Normalized -replace "`r", "`n"

    if (-not $Normalized.EndsWith("`n")) {
        $Normalized += "`n"
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Normalized,
        $Utf8NoBom
    )
}

$TAda =
    Split-Path -Parent $PSScriptRoot

$Matrix =
    Split-Path -Parent $TAda

$TestRoot =
    Split-Path -Parent $Matrix

$RepoRoot =
    Split-Path -Parent $TestRoot

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
    },
    @{
        Name = 'PARITY'
        Path = Join-Path $TAda 'parity\run-parity.ps1'
    },
    @{
        Name = 'RUNTIME'
        Path = Join-Path $TAda 'Runtime\run-runtime.ps1'
    },
    @{
        Name = 'HTTP'
        Path = Join-Path $TAda 'HTTP\run-http-reproduction.ps1'
    }
)

foreach ($Family in $Families) {
    if (-not (Test-Path -LiteralPath $Family.Path -PathType Leaf)) {
        throw "Verification family missing: $($Family.Path)"
    }
}

# ================================================================
# Ada runtime environment
#
# Public reproduction owns only the versioned toolchain locations.
# No developer-local repository dependency is introduced.
# ================================================================

$ToolchainRoot =
    Join-Path $env:LOCALAPPDATA 'alire\cache\toolchains'

$MsysRoot =
    Join-Path $env:LOCALAPPDATA 'alire\cache\msys64'

if (-not (Test-Path -LiteralPath $ToolchainRoot -PathType Container)) {
    throw 'Alire toolchain cache is missing.'
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

foreach ($Path in @(
    $GnatBin,
    $GprBin,
    $MingwBin
)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Runtime directory missing: $Path"
    }
}

$SodiumDll =
    Join-Path $MingwBin 'libsodium-26.dll'

if (-not (Test-Path -LiteralPath $SodiumDll -PathType Leaf)) {
    throw "libsodium runtime missing: $SodiumDll"
}

$RunRoot =
    Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        'hacp-sidecar-ada-1.1.1'

New-Item `
    -ItemType Directory `
    -Path $RunRoot `
    -Force |
    Out-Null

$EvidenceRoot =
    Join-Path $RunRoot 'evidence'

New-Item `
    -ItemType Directory `
    -Path $EvidenceRoot `
    -Force |
    Out-Null

$ResultPath =
    Join-Path $RunRoot 'verification-results.json'

Remove-Item `
    -LiteralPath $ResultPath `
    -Force `
    -ErrorAction SilentlyContinue

$Results =
    [System.Collections.Generic.List[object]]::new()

$OriginalPath =
    $env:Path

try {
    $env:Path =
        "$GnatBin;$GprBin;$MingwBin;$OriginalPath"

    Write-Host 'ADA_RUNTIME_ENVIRONMENT=PASS'

    foreach ($Family in $Families) {
        Write-Host
        Write-Host "=== FAMILY: $($Family.Name) ==="

        $FamilyLogPath =
            Join-Path `
                $EvidenceRoot `
                ($Family.Name.ToLowerInvariant() + '.log')

        try {
            # Each family owns its own PowerShell process.
            #
            # This is required because Runtime legitimately uses exit 0/1.
            # A family exit must never terminate the matrix orchestrator.
            #
            # Child stdout/stderr is captured as the public family record.
            $Output =
                @(
                    & pwsh `
                        -NoLogo `
                        -NoProfile `
                        -File $Family.Path `
                        2>&1
                )

            $FamilyRC =
                $LASTEXITCODE

            $FamilyText =
                (
                    $Output |
                    ForEach-Object {
                        [string]$_
                    }
                ) -join "`n"

            Write-Utf8Lf `
                -Path $FamilyLogPath `
                -Content $FamilyText

            Write-Host "FAMILY_EVIDENCE_LOG=$FamilyLogPath"

            $Output |
                ForEach-Object {
                    Write-Host ([string]$_)
                }

            if ($FamilyRC -ne 0) {
                throw (
                    "Family $($Family.Name) failed with exit code " +
                    "$FamilyRC"
                )
            }

            if ($Family.Name -eq 'HTTP') {
                $Text =
                    $Output -join "`n"

                foreach ($Marker in @(
                    'HTTP_NEGATIVE_403_DENY=PASS',
                    'HTTP_SINGLE_200_ALLOW=PASS',
                    'HTTP_CANONICAL_100_PLUS_5000=PASS',
                    'ADA_HTTP_REPRODUCTION=PASS'
                )) {
                    if (-not $Text.Contains($Marker)) {
                        throw "HTTP closure marker missing: $Marker"
                    }
                }
            }

            $Results.Add(
                [pscustomobject]@{
                    family = $Family.Name
                    status = 'PASS'
                }
            )

            Write-Host "FAMILY_$($Family.Name)=PASS"
        }
        catch {
            $Results.Add(
                [pscustomobject]@{
                    family = $Family.Name
                    status = 'FAIL'
                    error  = $_.Exception.Message
                }
            )

            Write-Host "FAMILY_$($Family.Name)=FAIL"
            Write-Host "FAMILY_ERROR=$($_.Exception.Message)"
        }
    }
}
finally {
    $env:Path =
        $OriginalPath

    Write-Host 'ADA_RUNTIME_PATH_RESTORED=YES'
}

$Results |
    ConvertTo-Json -Depth 10 |
    Set-Content `
        -LiteralPath $ResultPath `
        -Encoding utf8NoBOM

Write-Host
Write-Host "RESULT_FILE=$ResultPath"

$Failed =
    @(
        $Results |
            Where-Object status -ne 'PASS'
    )

if ($Failed.Count -ne 0) {
    Write-Host "FAILED_FAMILY_COUNT=$($Failed.Count)"
    throw 'One or more public verification families failed.'
}

Write-Host 'CORE_FAMILY=PASS'
Write-Host 'HC2_FAMILY=PASS'
Write-Host 'AUTHORIZATION_V2_FAMILY=PASS'
Write-Host 'PARITY_FAMILY=PASS'
Write-Host 'RUNTIME_FAMILY=PASS'
Write-Host 'HTTP_FUNCTIONAL_FAMILY=PASS'
Write-Host 'HTTP_WORKLOAD_FAMILY=PASS'
Write-Host 'FULL_PUBLIC_MATRIX_RUN=PASS'
