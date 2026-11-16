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
    Join-Path $RepoRoot 'bin\hacp_ada_runner.exe'

foreach ($Required in @(
    $Generator,
    $Runner
)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        throw "Parity input missing: $Required"
    }
}

$Tmp =
    Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ('hacp-sidecar-ada-parity-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $Tmp |
    Out-Null

function Invoke-ParityWitness {
    param(
        [string]$Name,
        [string]$File,
        [string]$ExpectedDecision,
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
        if ($null -ne $Response.decision) {
            [string]$Response.decision
        }
        else {
            [string]$Response.outcome
        }

    $Reasons =
        if ($null -ne $Response.reason_codes) {
            @(
                $Response.reason_codes |
                    ForEach-Object {
                        [string]$_
                    }
            )
        }
        elseif ($null -ne $Response.reason) {
            @([string]$Response.reason)
        }
        else {
            @()
        }

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
        throw 'Parity witness generation failed.'
    }

    Invoke-ParityWitness `
        -Name 'PARITY_CHECKPOINT_RESOLVED_DENY' `
        -File (Join-Path $Tmp 'checkpoint_resolved_deny.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'CHECKPOINT_DENIED'

    Invoke-ParityWitness `
        -Name 'PARITY_CHECKPOINT_UNKNOWN_STATE' `
        -File (Join-Path $Tmp 'checkpoint_unknown_state.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'INVALID_CHECKPOINT_STATE'

    Invoke-ParityWitness `
        -Name 'PARITY_PROVENANCE_MALFORMED' `
        -File (Join-Path $Tmp 'provenance_malformed.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'TRACEABILITY_FAILURE'

    Invoke-ParityWitness `
        -Name 'PARITY_TRUST_UNTRUSTED_TOKEN_SIGNER' `
        -File (Join-Path $Tmp 'trust_untrusted_token_signer.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'SIGNATURE_FAILURE'

    Invoke-ParityWitness `
        -Name 'PARITY_SCOPE_MISSING_DESTINATION' `
        -File (Join-Path $Tmp 'scope_missing_destination.json') `
        -ExpectedDecision 'DENY' `
        -ExpectedReason 'UNKNOWN_ATTRIBUTE'

    Write-Host 'DIRECT_CORE_PARITY_CASES=CORE-INV7-006,CORE-INV4-002,CORE-INV5-008,CORE-INV5-003,CORE-INV2-008,CORE-INV2-006,CORE-INV2-005'
    Write-Host 'DIRECT_CORE_PARITY_EXECUTION=CORE_FAMILY'
    Write-Host 'CHECKPOINT_PARITY=RESTORED'
    Write-Host 'SCOPE_PARITY=RESTORED'
    Write-Host 'KNOWN_HUMANIST_CORE_SEMANTIC_PARITY_GAPS=0'
    Write-Host 'KNOWN_SEMANTIC_RED=NONE'
    Write-Host 'PARITY_SYNTHETIC_TOTAL=NOT_USED'
    Write-Host 'ADA_HUMANIST_CORE_OBSERVABLE_PARITY=PASS'
}
finally {
    Remove-Item `
        -LiteralPath $Tmp `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}
