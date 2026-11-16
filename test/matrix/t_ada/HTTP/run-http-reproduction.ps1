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

$Proxy =
    Join-Path $RepoRoot 'bin\hacp_ada_proxy.exe'

$Generator =
    Join-Path $TAda 'Tools\generate-http-workload.py'

$Observer =
    Join-Path $PSScriptRoot 'observer\main.go'

foreach ($Required in @(
    $Proxy,
    $Generator,
    $Observer
)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        throw "HTTP reproduction input missing: $Required"
    }
}

function Get-FreeTcpPort {
    $Listener =
        [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Loopback,
            0
        )

    $Listener.Start()

    try {
        return (
            [System.Net.IPEndPoint]$Listener.LocalEndpoint
        ).Port
    }
    finally {
        $Listener.Stop()
    }
}

$Port = Get-FreeTcpPort
$Url  = "http://127.0.0.1:$Port/api/test"

$Tmp =
    Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ('hacp-sidecar-ada-http-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $Tmp |
    Out-Null

$Warmup =
    Join-Path $Tmp 'warmup.jsonl'

$Measured =
    Join-Path $Tmp 'measured.jsonl'

$Stdout =
    Join-Path $Tmp 'proxy-stdout.txt'

$Stderr =
    Join-Path $Tmp 'proxy-stderr.txt'

$Process = $null

try {
    python `
        $Generator `
        --count 100 `
        --out $Warmup `
        --method GET `
        --path /api/test

    if ($LASTEXITCODE -ne 0) {
        throw 'Warmup workload generation failed.'
    }

    python `
        $Generator `
        --count 5000 `
        --out $Measured `
        --method GET `
        --path /api/test

    if ($LASTEXITCODE -ne 0) {
        throw 'Measured workload generation failed.'
    }

    $Process =
        Start-Process `
            -FilePath $Proxy `
            -ArgumentList @("$Port") `
            -PassThru `
            -RedirectStandardOutput $Stdout `
            -RedirectStandardError $Stderr `
            -WindowStyle Hidden

    $Ready = $false

    for ($Attempt = 1; $Attempt -le 50; $Attempt++) {
        if ($Process.HasExited) {
            break
        }

        $Listener =
            Get-NetTCPConnection `
                -LocalAddress '127.0.0.1' `
                -LocalPort $Port `
                -State Listen `
                -ErrorAction SilentlyContinue

        if ($null -ne $Listener) {
            $Ready = $true
            break
        }

        Start-Sleep -Milliseconds 100
    }

    if ($Process.HasExited) {
        throw 'HTTP proxy exited during startup.'
    }

    if (-not $Ready) {
        throw 'HTTP proxy did not reach LISTEN state.'
    }

    # ------------------------------------------------------------
    # Functional negative
    # ------------------------------------------------------------

    $Negative =
        Invoke-WebRequest `
            -Uri $Url `
            -Method GET `
            -SkipHttpErrorCheck `
            -TimeoutSec 5

    $NegativeDecision =
        [string]$Negative.Headers['X-HACP-Decision']

    if ($Negative.StatusCode -ne 403) {
        throw (
            'Expected HTTP 403 without authorization material; ' +
            "observed $($Negative.StatusCode)"
        )
    }

    if ($NegativeDecision -ne 'DENY') {
        throw (
            'Expected HACP DENY without authorization material; ' +
            "observed $NegativeDecision"
        )
    }

    Write-Host 'HTTP_NEGATIVE_403_DENY=PASS'

    # ------------------------------------------------------------
    # Functional signed ALLOW
    # ------------------------------------------------------------

    $Record =
        Get-Content `
            -LiteralPath $Warmup `
            -TotalCount 1 |
        ConvertFrom-Json

    $Positive =
        Invoke-WebRequest `
            -Uri $Url `
            -Method GET `
            -Headers @{
                'X-HACP-Intent-Envelope' = [string]$Record.env
                'X-HACP-Decision-Token'  = [string]$Record.tok
            } `
            -SkipHttpErrorCheck `
            -TimeoutSec 5

    $PositiveDecision =
        [string]$Positive.Headers['X-HACP-Decision']

    if ($Positive.StatusCode -ne 200) {
        throw (
            "Expected signed HTTP 200; observed $($Positive.StatusCode)"
        )
    }

    if ($PositiveDecision -ne 'ALLOW') {
        throw (
            "Expected signed HACP ALLOW; observed $PositiveDecision"
        )
    }

    Write-Host 'HTTP_SINGLE_200_ALLOW=PASS'

    # ------------------------------------------------------------
    # Canonical workload
    # ------------------------------------------------------------

    & go run $Observer `
        -url $Url `
        -warmup-file $Warmup `
        -measured-file $Measured

    $ObserverRC = $LASTEXITCODE

    Write-Host "OBSERVER_RC=$ObserverRC"

    if ($ObserverRC -ne 0) {
        throw "HTTP workload observer failed with exit code $ObserverRC"
    }

    Write-Host 'HTTP_CANONICAL_100_PLUS_5000=PASS'
    Write-Host 'ADA_HTTP_REPRODUCTION=PASS'
}
finally {
    if (
        $null -ne $Process -and
        -not $Process.HasExited
    ) {
        Stop-Process `
            -Id $Process.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Remove-Item `
        -LiteralPath $Tmp `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}
