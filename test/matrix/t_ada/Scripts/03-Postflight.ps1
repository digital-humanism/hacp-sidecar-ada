$ErrorActionPreference = 'Stop'

$TAda =
    Split-Path -Parent $PSScriptRoot

$Matrix =
    Split-Path -Parent $TAda

$TestRoot =
    Split-Path -Parent $Matrix

$RepoRoot =
    Split-Path -Parent $TestRoot

Write-Host '=== PUBLIC MATRIX POSTFLIGHT ==='

if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
    $Status =
        @(
            git -C $RepoRoot status --short
        )

    Write-Host "GIT_WORKTREE_CHANGE_COUNT=$($Status.Count)"

    if ($Status.Count -ne 0) {
        Write-Host '=== WORKTREE CHANGES ==='
        $Status | ForEach-Object { Write-Host $_ }

        throw 'Postflight: public reproduction changed tracked worktree state.'
    }
}
else {
    Write-Host 'GIT_REPOSITORY=NOT_INITIALIZED'
}

Write-Host 'POSTFLIGHT_PROCESS_OWNERSHIP=CALLER_RESPONSIBILITY'
Write-Host 'POSTFLIGHT=PASS'
