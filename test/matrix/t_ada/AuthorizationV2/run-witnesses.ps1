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

$Generator =
    Join-Path $PSScriptRoot 'generate_witnesses.py'

$Runner =
    Join-Path $RepoRoot 'bin\hacp_ada_auth_v2_runner.exe'

foreach ($Required in @(
    $Generator,
    $Runner
)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        throw "Authorization-v2 input missing: $Required"
    }
}

$Tmp =
    Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ('hacp-sidecar-ada-auth-v2-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $Tmp |
    Out-Null

function Invoke-Witness {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$File,

        [Parameter(Mandatory)]
        [string]$ExpectedDecision,

        [Parameter(Mandatory)]
        [string]$ExpectedReason
    )

    $Witness =
        Get-Content `
            -LiteralPath $File `
            -Raw `
            -Encoding UTF8 |
        ConvertFrom-Json

    $Request =
        [ordered]@{
            protocol_version = '1'
            operation        = 'evaluate'
            vector_id        = $Name
            input            = $Witness.input
            policy_context   = $Witness.policy_context
        } |
        ConvertTo-Json `
            -Depth 100 `
            -Compress

    $Output =
        @(
            $Request |
                & $Runner
        )

    $RC =
        if ($null -eq $LASTEXITCODE) {
            0
        }
        else {
            $LASTEXITCODE
        }

    if ($RC -ne 0) {
        throw "$Name runner exit code $RC"
    }

    if ($Output.Count -lt 1) {
        throw "$Name returned no response"
    }

    $Response =
        $Output[-1] |
        ConvertFrom-Json

    $Decision =
        [string]$Response.decision

    $Reasons =
        @(
            $Response.reason_codes |
                ForEach-Object {
                    [string]$_
                }
        )

    if ($Decision -ne $ExpectedDecision) {
        throw (
            "$Name expected decision $ExpectedDecision, " +
            "observed $Decision"
        )
    }

    if ($Reasons -notcontains $ExpectedReason) {
        throw (
            "$Name expected reason $ExpectedReason, " +
            "observed: $($Reasons -join ',')"
        )
    }

    Write-Host "$Name=PASS"
}

try {
    python `
        $Generator `
        --out $Tmp

    if ($LASTEXITCODE -ne 0) {
        throw "Authorization-v2 witness generation failed."
    }

    Invoke-Witness `
        -Name 'ACTION_HASH_WITNESS' `
        -File (Join-Path $Tmp 'action_hash_witness.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'SIGNATURE_FAILURE'

    Invoke-Witness `
        -Name 'ENVELOPE_SIGNATURE_WITNESS' `
        -File (Join-Path $Tmp 'envelope_signature_witness.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'SIGNATURE_FAILURE'

    Invoke-Witness `
        -Name 'SIGNED_DENY_WITNESS' `
        -File (Join-Path $Tmp 'signed_deny_witness.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'POLICY_DENIED'

    Write-Host 'ADA_AUTHORIZATION_V2_WITNESSES=PASS'
    Write-Host 'RESULT=3/3'
    Write-Host 'ERRORS=NONE'
}
finally {
    Remove-Item `
        -LiteralPath $Tmp `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}
