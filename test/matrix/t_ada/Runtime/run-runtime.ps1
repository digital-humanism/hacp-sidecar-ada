& {
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

    $CoreVectors =
        Join-Path $RepoRoot 'vectors\core'

    $HC2Vectors =
        Join-Path $RepoRoot 'vectors\enforcement-v2'

    $TAda =
        Join-Path $Matrix 't_ada'

    $Fixtures =
        Join-Path $TAda 'fixtures'

    $Bin =
        Join-Path $RepoRoot 'bin'

    $Runner =
        Join-Path $Bin 'hacp_ada_runner.exe'

    $Proxy =
        Join-Path $Bin 'hacp_ada_proxy.exe'

    $Mcp =
        Join-Path $Bin 'hacp_ada_mcp.exe'

    $Control =
        Join-Path $Bin 'hacp_ada_controlplane.exe'


    $Integrated =
        Join-Path $Bin 'hacp_ada_integrated.exe'

    $McpFixture =
        Join-Path $Fixtures 'mcp-allow.json'
    $Failures =
        [System.Collections.Generic.List[string]]::new()

    $Results =
        [System.Collections.Generic.List[object]]::new()

    function Assert-True {
        param(
            [bool]$Condition,
            [string]$Message
        )

        if (-not $Condition) {
            throw $Message
        }
    }

    function Get-InputObject {
        param($Vector)

        if ($null -ne $Vector.inputs) {
            return $Vector.inputs
        }

        if ($null -ne $Vector.input) {
            return $Vector.input
        }

        throw 'Vector has neither inputs nor input.'
    }

    function Get-ExpectedOutcome {
        param($Vector)

        if ($null -eq $Vector.expected) {
            return $null
        }

        if ($null -ne $Vector.expected.outcome) {
            return [string]$Vector.expected.outcome
        }

        if ($null -ne $Vector.expected.decision) {
            return [string]$Vector.expected.decision
        }

        return $null
    }

    function Get-ObservedDecision {
        param($Response)

        if ($null -ne $Response.decision) {
            return [string]$Response.decision
        }

        if ($null -ne $Response.outcome) {
            return [string]$Response.outcome
        }

        return ''
    }

    function Get-ObservedReasons {
        param($Response)

        if ($null -ne $Response.reason_codes) {
            return @($Response.reason_codes | ForEach-Object { [string]$_ })
        }

        if ($null -ne $Response.reason) {
            return @([string]$Response.reason)
        }

        return @()
    }

    function Invoke-Surface {
        param(
            [string]$Name,
            [scriptblock]$Body
        )

        $Watch =
            [System.Diagnostics.Stopwatch]::StartNew()

        try {
            & $Body

            $Watch.Stop()

            $Result =
                [pscustomobject]@{
                    Surface = $Name
                    Status  = 'PASS'
                    Ms      = $Watch.Elapsed.TotalMilliseconds
                }

            $Results.Add($Result)

            Write-Host (
                "{0}=PASS | {1:F3} ms" -f
                $Name,
                $Watch.Elapsed.TotalMilliseconds
            )
        }
        catch {
            $Watch.Stop()

            $Message =
                $_.Exception.Message

            $Failures.Add(
                "$Name | $Message"
            )

            $Result =
                [pscustomobject]@{
                    Surface = $Name
                    Status  = 'FAIL'
                    Ms      = $Watch.Elapsed.TotalMilliseconds
                }

            $Results.Add($Result)

            Write-Host (
                "{0}=FAIL | {1:F3} ms | {2}" -f
                $Name,
                $Watch.Elapsed.TotalMilliseconds,
                $Message
            )
        }
    }

    function ConvertTo-Base64UrlUtf8 {
        param(
            [Parameter(Mandatory)]
            [string]$Text
        )

        $Bytes =
            [System.Text.Encoding]::UTF8.GetBytes($Text)

        return [Convert]::ToBase64String($Bytes).
            TrimEnd('=').
            Replace('+','-').
            Replace('/','_')
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

    Write-Host '============================================================'
    Write-Host 'HACP SIDECAR ADA — RUNTIME SWEEP'
    Write-Host '============================================================'

    # ---------------------------------------------------------
    # Identity / preflight
    # ---------------------------------------------------------

    Write-Host
    Write-Host '=== PREFLIGHT ==='

    foreach ($Exe in @(
        $Runner,
        $Proxy,
        $Mcp,
        $Control,
        $Integrated
    )) {
        Assert-True `
            (Test-Path -LiteralPath $Exe) `
            "Missing executable: $Exe"
    }

    Assert-True `
        (Test-Path -LiteralPath $CoreVectors) `
        "Missing canonical Core vectors."

    Assert-True `
        (Test-Path -LiteralPath $HC2Vectors) `
        "Missing canonical HC2 vectors."

    Assert-True `
        (Test-Path -LiteralPath $McpFixture) `
        "Missing matrix MCP implementation fixture."

    $ActualMcpHash =
        (Get-FileHash `
            -LiteralPath $McpFixture `
            -Algorithm SHA256).Hash
    Write-Host "RUNNER_SHA256=$(
        (Get-FileHash -LiteralPath $Runner -Algorithm SHA256).Hash
    )"

    Write-Host "PROXY_SHA256=$(
        (Get-FileHash -LiteralPath $Proxy -Algorithm SHA256).Hash
    )"

    Write-Host "MCP_SHA256=$(
        (Get-FileHash -LiteralPath $Mcp -Algorithm SHA256).Hash
    )"

    Write-Host "CONTROLPLANE_SHA256=$(
        (Get-FileHash -LiteralPath $Control -Algorithm SHA256).Hash
    )"


    Write-Host "INTEGRATED_SHA256=$(
        (Get-FileHash -LiteralPath $Integrated -Algorithm SHA256).Hash
    )"

    Write-Host "MCP_FIXTURE_SHA256=$ActualMcpHash"

    # =========================================================
    # RUNTIME-1
    # Canonical Core runtime vectors: CORE-RUNTIME-001..005
    # =========================================================

    Write-Host
    Write-Host '=== RUNTIME-1 — CANONICAL CORE RUNTIME VECTORS ==='

    Invoke-Surface 'RUNTIME_1_CORE_RUNTIME' {

        $Files =
            @(
                Get-ChildItem `
                    -LiteralPath $CoreVectors `
                    -File `
                    -Filter 'runtime_*.json' |
                Sort-Object Name
            )

        Assert-True `
            ($Files.Count -eq 5) `
            "Expected exactly 5 canonical runtime vectors; observed $($Files.Count)."

        foreach ($File in $Files) {
            $Vector =
                Get-Content `
                    -LiteralPath $File.FullName `
                    -Raw `
                    -Encoding UTF8 |
                ConvertFrom-Json

            $Input =
                Get-InputObject $Vector

            $Request =
                [ordered]@{
                    input          = $Input
                    policy_context = $Vector.policy_context
                }

            $RequestJson =
                $Request |
                ConvertTo-Json `
                    -Depth 100 `
                    -Compress

            $VectorWatch =
                [System.Diagnostics.Stopwatch]::StartNew()

            $Output =
                @(
                    $RequestJson |
                    & $Runner
                )

            $RC =
                if ($null -eq $LASTEXITCODE) {
                    0
                }
                else {
                    $LASTEXITCODE
                }

            $VectorWatch.Stop()

            Assert-True `
                ($RC -eq 0) `
                "$($Vector.test_id): runner exit code $RC."

            Assert-True `
                ($Output.Count -ge 1) `
                "$($Vector.test_id): no runner response."

            $Response =
                $Output[-1] |
                ConvertFrom-Json

            $Expected =
                Get-ExpectedOutcome $Vector

            $Observed =
                Get-ObservedDecision $Response

            Assert-True `
                ($Observed -eq $Expected) `
                "$($Vector.test_id): expected $Expected, observed $Observed."

            $ExpectedReasons =
                if ($null -ne $Vector.expected.reason_codes) {
                    @(
                        $Vector.expected.reason_codes |
                        ForEach-Object { [string]$_ }
                    )
                }
                else {
                    @()
                }

            if ($ExpectedReasons.Count -gt 0) {
                $ObservedReasons =
                    Get-ObservedReasons $Response

                foreach ($Reason in $ExpectedReasons) {
                    Assert-True `
                        ($ObservedReasons -contains $Reason) `
                        "$($Vector.test_id): missing expected reason $Reason."
                }
            }

            Write-Host (
                "[PASS] {0} | {1:F3} ms" -f
                $Vector.test_id,
                $VectorWatch.Elapsed.TotalMilliseconds
            )
        }
    }

    # =========================================================
    # RUNTIME-2
    # HTTP transport using derived transport-bound fixture.
    #
    # The fixture is derived from canonical ENF-HC2-001
    # semantics, but its proposed action / action_hash /
    # DecisionToken signature are rebound to the action
    # synthesized by the Ada HTTP adapter.
    #
    # The canonical HC2 vector is not modified.
    # =========================================================

    Write-Host
    Write-Host '=== RUNTIME-2 — HTTP TRANSPORT / DERIVED HC2 FIXTURE ==='

    Invoke-Surface 'RUNTIME_2_HTTP' {

        $HttpFixture =
            Join-Path $Fixtures 'http-allow.json'
        Assert-True `
            (Test-Path -LiteralPath $HttpFixture) `
            'Missing derived HTTP transport fixture.'

        $ActualHttpFixtureHash =
            (Get-FileHash `
                -LiteralPath $HttpFixture `
                -Algorithm SHA256).Hash
        $F =
            Get-Content `
                -LiteralPath $HttpFixture `
                -Raw `
                -Encoding UTF8 |
            ConvertFrom-Json

        Assert-True `
            ([string]$F.classification -eq 'IMPLEMENTATION_TRANSPORT_FIXTURE') `
            'Unexpected HTTP fixture classification.'

        Assert-True `
            ([string]$F.canonical_test_id -eq 'ENF-HC2-001') `
            'Unexpected canonical source test id.'

        Assert-True `
            ($F.derivation.canonical_vector_modified -eq $false) `
            'Fixture incorrectly claims canonical mutation.'

        Assert-True `
            ($F.derivation.decision_token_resigned -eq $true) `
            'Fixture does not record DecisionToken re-signing.'

        $EnvJson =
            $F.intent_envelope |
            ConvertTo-Json `
                -Depth 100 `
                -Compress

        $TokJson =
            $F.decision_token |
            ConvertTo-Json `
                -Depth 100 `
                -Compress

        $EnvHeader =
            ConvertTo-Base64UrlUtf8 $EnvJson

        $TokHeader =
            ConvertTo-Base64UrlUtf8 $TokJson

        $Port =
            Get-FreeTcpPort

        $Tmp =
            Join-Path `
                ([System.IO.Path]::GetTempPath()) `
                ("hacp-runtime-http-" + [guid]::NewGuid().ToString('N'))

        New-Item `
            -ItemType Directory `
            -Path $Tmp |
        Out-Null

        $Stdout =
            Join-Path $Tmp 'stdout.txt'

        $Stderr =
            Join-Path $Tmp 'stderr.txt'

        $Process =
            $null

        try {
            $Process =
                Start-Process `
                    -FilePath $Proxy `
                    -ArgumentList @("$Port") `
                    -PassThru `
                    -RedirectStandardOutput $Stdout `
                    -RedirectStandardError $Stderr `
                    -WindowStyle Hidden

            $Ready =
                $false

            $StartupWatch =
                [System.Diagnostics.Stopwatch]::StartNew()

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

            $StartupWatch.Stop()

            Assert-True `
                (-not $Process.HasExited) `
                'HTTP proxy exited during startup.'

            Assert-True `
                $Ready `
                'HTTP proxy did not reach LISTEN state.'

            $Target =
                [string]$F.http_request.request_target

            $Method =
                [string]$F.http_request.method

            $HttpWatch =
                [System.Diagnostics.Stopwatch]::StartNew()

            $Response =
                Invoke-WebRequest `
                    -Uri "http://127.0.0.1:$Port$Target" `
                    -Method $Method `
                    -Headers @{
                        'X-HACP-Intent-Envelope' = $EnvHeader
                        'X-HACP-Decision-Token'  = $TokHeader
                    } `
                    -SkipHttpErrorCheck `
                    -TimeoutSec 5

            $HttpWatch.Stop()

            $Decision =
                [string]$Response.Headers['X-HACP-Decision']

            Assert-True `
                ($Response.StatusCode -eq 200) `
                "HTTP status expected 200, observed $($Response.StatusCode)."

            Assert-True `
                ($Decision -eq 'ALLOW') `
                "HTTP decision expected ALLOW, observed $Decision."

            $Body =
                $Response.Content |
                ConvertFrom-Json

            Assert-True `
                ([string]$Body.decision -eq 'ALLOW') `
                'HTTP body decision expected ALLOW.'

            Write-Host "HTTP_FIXTURE_SHA256=$ActualHttpFixtureHash"
            Write-Host "HTTP_CANONICAL_SOURCE=$($F.canonical_test_id)"
            Write-Host "HTTP_ORIGINAL_ACTION_HASH=$($F.derivation.original_action_hash)"
            Write-Host "HTTP_DERIVED_ACTION_HASH=$($F.derivation.derived_action_hash)"
            Write-Host "HTTP_STARTUP_READY_MS=$($StartupWatch.Elapsed.TotalMilliseconds.ToString('F3'))"
            Write-Host "HTTP_REQUEST_WALL_MS=$($HttpWatch.Elapsed.TotalMilliseconds.ToString('F3'))"
            Write-Host "HTTP_STATUS=$($Response.StatusCode)"
            Write-Host "HTTP_DECISION=$Decision"
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
    }
    # =========================================================
    # RUNTIME-3
    # MCP JSON-RPC over stdio — implementation fixture
    # =========================================================

    Write-Host
    Write-Host '=== RUNTIME-3 — MCP STDIO ==='

    Invoke-Surface 'RUNTIME_3_MCP' {

        $Request =
            Get-Content `
                -LiteralPath $McpFixture `
                -Raw `
                -Encoding UTF8

        $Output =
            @(
                $Request |
                & $Mcp
            )

        $RC =
            if ($null -eq $LASTEXITCODE) {
                0
            }
            else {
                $LASTEXITCODE
            }

        Assert-True `
            ($RC -eq 0) `
            "MCP exit code $RC."

        Assert-True `
            ($Output.Count -ge 1) `
            'MCP returned no response.'

        $Response =
            $Output[-1] |
            ConvertFrom-Json

        Assert-True `
            ($null -eq $Response.error) `
            "MCP returned error: $($Response.error.message)"

        Assert-True `
            ($null -ne $Response.result) `
            'MCP result is missing.'

        $Text =
            [string]$Response.result.content[0].text

        Assert-True `
            ($Text -eq 'HACP ALLOW') `
            "MCP expected HACP ALLOW, observed: $Text"

        Write-Host 'MCP_RESULT=HACP ALLOW'
        Write-Host 'MCP_INPUT_CLASS=IMPLEMENTATION_TRANSPORT_FIXTURE'
    }

    # =========================================================
    # RUNTIME-4
    # Control plane JSON-RPC-like protocol over stdio
    # =========================================================

    Write-Host
    Write-Host '=== RUNTIME-4 — CONTROL PLANE STDIO ==='

    Invoke-Surface 'RUNTIME_4_CONTROL_STDIO' {

        $Requests =
            @(
                '{"id":1,"method":"revision"}',
                '{"id":2,"method":"snapshot"}',
                '{"id":3,"method":"events_after","after_revision":0}'
            )

        $Output =
            @(
                $Requests |
                & $Control
            )

        $RC =
            if ($null -eq $LASTEXITCODE) {
                0
            }
            else {
                $LASTEXITCODE
            }

        Assert-True `
            ($RC -eq 0) `
            "Control-plane stdio exit code $RC."

        Assert-True `
            ($Output.Count -eq 3) `
            "Expected 3 control-plane responses; observed $($Output.Count)."

        $Revision =
            $Output[0] |
            ConvertFrom-Json

        $Snapshot =
            $Output[1] |
            ConvertFrom-Json

        $Events =
            $Output[2] |
            ConvertFrom-Json

        Assert-True `
            ($Revision.ok -eq $true) `
            'revision response not ok.'

        Assert-True `
            ([int64]$Revision.revision -ge 1) `
            "revision expected >= 1."

        Assert-True `
            ($Snapshot.ok -eq $true) `
            'snapshot response not ok.'

        $SnapshotIds =
            @(
                $Snapshot.snapshot.entries |
                ForEach-Object {
                    [string]$_.subject_id
                }
            )

        Assert-True `
            ($SnapshotIds -contains 'test-revoked-key-001') `
            'seed revocation missing from snapshot.'

        Assert-True `
            ($Events.ok -eq $true) `
            'events_after response not ok.'

        $EventIds =
            @(
                $Events.events |
                ForEach-Object {
                    [string]$_.subject_id
                }
            )

        Assert-True `
            ($EventIds -contains 'test-revoked-key-001') `
            'seed revocation missing from events_after.'

        Write-Host "CONTROL_REVISION=$($Revision.revision)"
        Write-Host "CONTROL_SNAPSHOT_ENTRIES=$($Snapshot.snapshot.entries.Count)"
        Write-Host "CONTROL_EVENTS_AFTER_0=$($Events.events.Count)"
    }

    # =========================================================
    # RUNTIME-6
    # Integrated evaluate -> revoke -> evaluate
    # canonical Core runtime input
    # =========================================================

    Write-Host
    Write-Host '=== RUNTIME-6 — INTEGRATED REVOKE FLOW ==='

    Invoke-Surface 'RUNTIME_6_INTEGRATED' {

        $VectorPath =
            Join-Path $CoreVectors 'runtime_001_golden.json'

        Assert-True `
            (Test-Path -LiteralPath $VectorPath) `
            'Missing canonical runtime_001_golden.json.'

        $Vector =
            Get-Content `
                -LiteralPath $VectorPath `
                -Raw `
                -Encoding UTF8 |
            ConvertFrom-Json

        $Input =
            Get-InputObject $Vector

        $Request =
            [ordered]@{
                input = $Input
            } |
            ConvertTo-Json `
                -Depth 100 `
                -Compress

        $Output =
            @(
                $Request |
                & $Integrated
            )

        $RC =
            if ($null -eq $LASTEXITCODE) {
                0
            }
            else {
                $LASTEXITCODE
            }

        Assert-True `
            ($RC -eq 0) `
            "Integrated exit code $RC."

        Assert-True `
            ($Output.Count -ge 1) `
            'Integrated runner returned no response.'

        $Response =
            $Output[-1] |
            ConvertFrom-Json

        Assert-True `
            ($Response.pass -eq $true) `
            'Integrated self-check returned pass=false.'

        Assert-True `
            ([string]$Response.baseline_decision -eq 'ALLOW') `
            "Integrated baseline expected ALLOW."

        Assert-True `
            ($Response.revoke_committed -eq $true) `
            'Integrated revoke was not committed.'

        Assert-True `
            ([string]$Response.post_revoke_decision -eq 'DENY') `
            'Integrated post-revoke decision expected DENY.'

        Assert-True `
            ([string]$Response.post_revoke_reason -eq 'TOKEN_REVOKED') `
            "Integrated post-revoke reason expected TOKEN_REVOKED."

        Write-Host "INTEGRATED_BASELINE=$($Response.baseline_decision)"
        Write-Host "INTEGRATED_REVOKE_COMMITTED=$($Response.revoke_committed)"
        Write-Host "INTEGRATED_SNAPSHOT_REVISION=$($Response.snapshot_revision)"
        Write-Host "INTEGRATED_POST_REVOKE=$($Response.post_revoke_decision)"
        Write-Host "INTEGRATED_REASON=$($Response.post_revoke_reason)"
    }

    # =========================================================
    # Final result
    # =========================================================

    Write-Host
    Write-Host '=== RUNTIME TIMING SUMMARY ==='

    foreach ($Result in $Results) {
        Write-Host (
            "{0} | {1} | {2:F3} ms" -f
            $Result.Surface,
            $Result.Status,
            $Result.Ms
        )
    }

    Write-Host
    Write-Host '=== RUNTIME ERRORS ==='

    if ($Failures.Count -eq 0) {
        Write-Host 'ERRORS=NONE'
    }
    else {
        foreach ($Failure in $Failures) {
            Write-Host $Failure
        }
    }

    Write-Host
    Write-Host '=== RUNTIME FINAL ==='
    Write-Host "RUNTIME_SURFACES=$($Results.Count)"
    Write-Host "RUNTIME_PASSED=$(($Results | Where-Object Status -eq 'PASS').Count)"
    Write-Host "RUNTIME_FAILED=$(($Results | Where-Object Status -eq 'FAIL').Count)"
    Write-Host 'CANONICAL_CORE_RUNTIME_VECTORS=5'
    Write-Host 'HTTP_INPUT=CANONICAL_HC2_VECTOR'
    Write-Host 'MCP_INPUT=IMPLEMENTATION_TRANSPORT_FIXTURE'
    Write-Host 'DEV_RUNTIME_DEPENDENCY=NONE'
    Write-Host 'SOURCE_MUTATION=NONE'

    if ($Failures.Count -gt 0) {
        Write-Host 'ADA_RUNTIME=FAIL'
        exit 1
    }

    Write-Host 'ADA_RUNTIME=PASS'
    exit 0
}
