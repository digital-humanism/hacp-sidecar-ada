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

$Preflight =
    Join-Path $PSScriptRoot '00-Preflight.ps1'

& $Preflight

if ($LASTEXITCODE -notin @(0, $null)) {
    throw "Preflight failed with exit code $LASTEXITCODE"
}

Set-Location -LiteralPath $RepoRoot

$RunRoot =
    Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        'hacp-sidecar-ada-1.1.1'

if (Test-Path -LiteralPath $RunRoot) {
    Remove-Item `
        -LiteralPath $RunRoot `
        -Recurse `
        -Force
}

$EvidenceRoot =
    Join-Path $RunRoot 'evidence'

New-Item `
    -ItemType Directory `
    -Path $EvidenceRoot `
    -Force |
    Out-Null

$RunContext =
    [ordered]@{
        run_id =
            [guid]::NewGuid().ToString()

        release =
            '1.1.1'

        implementation =
            'Ada/SPARK'

        started_at =
            (Get-Date).ToString('o')

        repository_root =
            $RepoRoot
    }

$RunContext |
    ConvertTo-Json -Depth 10 |
    Set-Content `
        -LiteralPath (Join-Path $RunRoot 'run-context.json') `
        -Encoding utf8NoBOM

Write-Host "RUN_ID=$($RunContext.run_id)"
Write-Host "RUN_STARTED_AT=$($RunContext.started_at)"
Write-Host "RUN_ROOT=$RunRoot"

$Bin =
    Join-Path $RepoRoot 'bin'

$Obj =
    Join-Path $RepoRoot 'obj'

foreach ($Dir in @(
    $Bin,
    $Obj
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

Write-Host '=== PUBLIC ADA CLEAN BUILD ==='

& alr exec -- gprbuild `
    -P (Join-Path $RepoRoot 'hacp_ada.gpr')

$BuildExit = $LASTEXITCODE

Write-Host "BUILD_EXIT_CODE=$BuildExit"

if ($BuildExit -ne 0) {
    throw "Ada build failed with exit code $BuildExit"
}

$Executables =
    @(
        Get-ChildItem `
            -LiteralPath $Bin `
            -File `
            -Filter '*.exe'
    )

$ExpectedExecutables = @(
    'hacp_ada_auth_v2_runner.exe',
    'hacp_ada_controlplane.exe',
    'hacp_ada_integrated.exe',
    'hacp_ada_mcp.exe',
    'hacp_ada_proxy.exe',
    'hacp_ada_runner.exe'
)

$ActualExecutableNames =
    @(
        $Executables |
            Sort-Object Name |
            ForEach-Object Name
    )

$ExecutableDiff =
    @(
        Compare-Object `
            $ExpectedExecutables `
            $ActualExecutableNames
    )

if ($ExecutableDiff.Count -ne 0) {
    Write-Host '=== EXECUTABLE SET DIFF ==='
    $ExecutableDiff | Format-Table -AutoSize

    throw 'Unexpected executable set.'
}

Write-Host "EXE_COUNT=$($Executables.Count)"

foreach ($Exe in ($Executables | Sort-Object Name)) {
    Write-Host "EXE=$($Exe.Name)"
}

Write-Host 'ADA_BUILD=PASS'
