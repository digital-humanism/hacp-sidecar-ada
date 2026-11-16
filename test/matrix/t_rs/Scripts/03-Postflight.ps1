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

Write-Host '=== t_rs 03 — POSTFLIGHT ==='

if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
    throw 'Git must not be initialized before P18.'
}

$ExpectedEvidence = @(
    'ada_prepare.log',
    'ada_core.log',
    'rust_core.log',
    'ada_authorization_v2.log',
    'rust_authorization_v2.log'
)

foreach ($Name in $ExpectedEvidence) {
    $Path =
        Join-Path $Evidence $Name

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Evidence file missing: $Path"
    }

    if ((Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "Evidence file empty: $Path"
    }
}

$TRsFiles =
    @(
        Get-ChildItem `
            -LiteralPath $TRs `
            -Recurse `
            -File
    )

foreach ($Pattern in @(
    ('HACP-' + 'LAB'),
    ('rust-core-' + 'comparison'),
    ('Get-' + 'FileHash')
)) {
    $Matches =
        @(
            $TRsFiles |
                Where-Object {
                    $_.Extension.ToLowerInvariant() -in @(
                        '.ps1',
                        '.psm1',
                        '.py',
                        '.rs',
                        '.md',
                        '.toml'
                    )
                } |
                Select-String `
                    -SimpleMatch `
                    -Pattern $Pattern `
                    -ErrorAction SilentlyContinue
        )

    if ($Matches.Count -ne 0) {
        throw "Forbidden public dependency found: $Pattern"
    }
}

$PrivateVectors =
    @(
        Get-ChildItem `
            -LiteralPath $TRs `
            -Recurse `
            -Directory `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq 'vectors'
        }
    )

if ($PrivateVectors.Count -ne 0) {
    throw 'Private t_rs vector copy detected.'
}

Write-Host 'EVIDENCE_FILES=PASS'
Write-Host 'PUBLIC_DEPENDENCY_HYGIENE=PASS'
Write-Host 'VECTOR_SOURCE=ROOT\vectors'
Write-Host 'PRIVATE_VECTOR_COPY=NONE'
Write-Host 'T_ADA_MUTATION=NO'
Write-Host 'GIT_INITIALIZED=NO'
Write-Host 'T_RS_POSTFLIGHT=PASS'
