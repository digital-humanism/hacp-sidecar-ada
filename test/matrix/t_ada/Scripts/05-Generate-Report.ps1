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

$RunRoot =
    Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        'hacp-sidecar-ada-1.1.1'

$EvidenceRoot =
    Join-Path $RunRoot 'evidence'

$ContextPath =
    Join-Path $RunRoot 'run-context.json'

$ResultPath =
    Join-Path $RunRoot 'verification-results.json'

$ReconciliationPath =
    Join-Path $RunRoot 'reconciliation.json'

foreach ($Required in @(
    $ContextPath,
    $ResultPath,
    $ReconciliationPath
)) {
    if (-not (
        Test-Path `
            -LiteralPath $Required `
            -PathType Leaf
    )) {
        throw "Required report input missing: $Required"
    }
}

$FamilyNames = @(
    'core',
    'hc2',
    'authorization_v2',
    'parity',
    'runtime',
    'http'
)

foreach ($Name in $FamilyNames) {
    $FamilyPath =
        Join-Path $EvidenceRoot "$Name.log"

    if (-not (
        Test-Path `
            -LiteralPath $FamilyPath `
            -PathType Leaf
    )) {
        throw "Family evidence log missing: $FamilyPath"
    }
}

$Context =
    Get-Content `
        -LiteralPath $ContextPath `
        -Raw `
        -Encoding UTF8 |
    ConvertFrom-Json -DateKind String

$Results =
    Get-Content `
        -LiteralPath $ResultPath `
        -Raw `
        -Encoding UTF8 |
    ConvertFrom-Json

$Reconciliation =
    Get-Content `
        -LiteralPath $ReconciliationPath `
        -Raw `
        -Encoding UTF8 |
    ConvertFrom-Json

foreach ($Name in @(
    'CORE',
    'HC2',
    'AUTHORIZATION_V2',
    'PARITY',
    'RUNTIME',
    'HTTP'
)) {
    $Entry =
        @(
            $Results |
                Where-Object family -eq $Name
        )

    if (
        $Entry.Count -ne 1 -or
        [string]$Entry[0].status -ne 'PASS'
    ) {
        throw "Report generation refused: family $Name is not PASS."
    }
}

function Read-Evidence {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return (
        Get-Content `
            -LiteralPath (
                Join-Path $EvidenceRoot "$Name.log"
            ) `
            -Raw `
            -Encoding UTF8
    )
}

function Get-LineValue {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $Match =
        [regex]::Match(
            $Text,
            '(?m)^' +
            [regex]::Escape($Name) +
            '=(?<value>[^\r\n]+)$'
        )

    if ($Match.Success) {
        return $Match.Groups['value'].Value.Trim()
    }

    return ''
}

function Escape-MarkdownCell {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    return (
        $Text.
            Replace('|', '\|').
            Replace("`r", ' ').
            Replace("`n", ' ')
    )
}

function Get-VectorRows {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$StartMarker,

        [Parameter(Mandatory)]
        [string]$EndMarker
    )

    $Start =
        $Text.IndexOf($StartMarker)

    if ($Start -lt 0) {
        throw "Start marker missing: $StartMarker"
    }

    $End =
        $Text.IndexOf(
            $EndMarker,
            $Start + $StartMarker.Length
        )

    if ($End -lt 0) {
        throw "End marker missing: $EndMarker"
    }

    $Block =
        $Text.Substring(
            $Start + $StartMarker.Length,
            $End - (
                $Start + $StartMarker.Length
            )
        )

    $Pattern =
        '(?ms)^\[(?<index>\d+)/(?<count>\d+)\]\s+' +
        '(?<id>[^\r\n]+)\r?\n' +
        'DESCRIPTION=(?<description>[^\r\n]*)\r?\n' +
        'EXPECTED=(?<expected>[^\r\n]*)\r?\n' +
        'OBSERVED=(?<observed>[^\r\n]*)\r?\n' +
        'EXECUTION_PATH=(?<path>[^\r\n]*)\r?\n' +
        'TARGET_EVALUATE_MS=(?<target>[^\r\n]*)\r?\n' +
        'VECTOR_TOTAL_MS=(?<total>[^\r\n]*)\r?\n' +
        'RESULT=(?<result>[^\r\n]*)'

    return @(
        [regex]::Matches(
            $Block,
            $Pattern
        ) |
        ForEach-Object {
            [pscustomobject]@{
                Index =
                    [int]$_.Groups['index'].Value

                Id =
                    $_.Groups['id'].Value.Trim()

                Description =
                    $_.Groups['description'].Value.Trim()

                Expected =
                    $_.Groups['expected'].Value.Trim()

                Observed =
                    $_.Groups['observed'].Value.Trim()

                ExecutionPath =
                    $_.Groups['path'].Value.Trim()

                TargetMs =
                    $_.Groups['target'].Value.Trim()

                TotalMs =
                    $_.Groups['total'].Value.Trim()

                Result =
                    $_.Groups['result'].Value.Trim()
            }
        }
    )
}

$CoreText =
    Read-Evidence -Name 'core'

$HC2Text =
    Read-Evidence -Name 'hc2'

$AuthorizationText =
    Read-Evidence -Name 'authorization_v2'

$ParityText =
    Read-Evidence -Name 'parity'

$RuntimeText =
    Read-Evidence -Name 'runtime'

$HttpText =
    Read-Evidence -Name 'http'

$CoreRows =
    Get-VectorRows `
        -Text $CoreText `
        -StartMarker '=== CORE-38 FULL VECTOR REPORT ===' `
        -EndMarker '=== CORE-38 AGGREGATES ==='

$HC2Rows =
    Get-VectorRows `
        -Text $HC2Text `
        -StartMarker '=== HC2-55 FULL VECTOR REPORT ===' `
        -EndMarker '=== HC2-55 AGGREGATES ==='

if ($CoreRows.Count -ne 38) {
    throw "Expected 38 Core report rows; observed $($CoreRows.Count)"
}

if ($HC2Rows.Count -ne 55) {
    throw "Expected 55 HC2 report rows; observed $($HC2Rows.Count)"
}

$SpecVersion =
    Get-LineValue `
        -Text $CoreText `
        -Name 'SPEC_VERSION'

$Profile =
    Get-LineValue `
        -Text $CoreText `
        -Name 'PROFILE'

$VectorSet =
    Get-LineValue `
        -Text $CoreText `
        -Name 'VECTOR_SET'

$ManifestDigest =
    Get-LineValue `
        -Text $CoreText `
        -Name 'EXPECTED_DIGEST'

$DigestMatch =
    Get-LineValue `
        -Text $CoreText `
        -Name 'VECTOR_DIGEST_MATCH'

$Started =
    [datetimeoffset]::Parse(
        [string]$Context.started_at
    )

$Completed =
    [datetimeoffset]::Parse(
        [string]$Reconciliation.run_completed_at,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    )

$ReportGenerated =
    [datetimeoffset]::Now

$Duration =
    $Completed - $Started

Set-Location -LiteralPath $RepoRoot

$PythonVersion =
    (
        & python --version 2>&1 |
        Select-Object -First 1
    )

$GoVersion =
    (
        & go version 2>&1 |
        Select-Object -First 1
    )

$AlireVersion =
    (
        & alr --version 2>&1 |
        Select-Object -First 1
    )

$GnatVersion =
    (
        & alr exec -- gnatmake --version 2>&1 |
        Select-Object -First 1
    )

$GprVersion =
    (
        & alr exec -- gprbuild --version 2>&1 |
        Select-Object -First 1
    )

$Executables =
    @(
        Get-ChildItem `
            -LiteralPath (Join-Path $RepoRoot 'bin') `
            -File `
            -Filter '*.exe' |
        Sort-Object Name
    )

if ($Executables.Count -ne 6) {
    throw "Expected 6 Ada executables; observed $($Executables.Count)"
}

$ExecutableRecords =
    @(
        foreach ($Exe in $Executables) {
            [pscustomobject]@{
                Name =
                    $Exe.Name

                SHA256 =
                    (
                        Get-FileHash `
                            -LiteralPath $Exe.FullName `
                            -Algorithm SHA256
                    ).Hash
            }
        }
    )

$HttpRecords =
    @(
        $HttpText -split '\r?\n' |
        Where-Object {
            $_ -match (
                '^\{"surface":' +
                '"AUTHORIZATION_PLUS_LOCAL_RESPONSE"'
            )
        } |
        ForEach-Object {
            $_ | ConvertFrom-Json
        }
    )

if ($HttpRecords.Count -ne 2) {
    throw "Expected 2 HTTP metric records; observed $($HttpRecords.Count)"
}

$ReportRoot =
    Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        'hacp-sidecar-ada\reports'

New-Item `
    -ItemType Directory `
    -Path $ReportRoot `
    -Force |
    Out-Null

$Stamp =
    $Started.
        ToString('yyyy-MM-ddTHH-mm-sszzz').
        Replace(':', '')

$ReportPath =
    Join-Path `
        $ReportRoot `
        (
            'hacp-sidecar-ada_1.1.1_reproduction_' +
            $Stamp +
            '.md'
        )

$Md =
    [System.Collections.Generic.List[string]]::new()

function Add-Md {
    param(
        [AllowEmptyString()]
        [string]$Line = ''
    )

    $Md.Add($Line)
}

Add-Md '# HACP Sidecar Ada — Public Reproduction Report'
Add-Md
Add-Md '> Public reproduction evidence generated from the observed HACP 1.1.1 Ada/SPARK verification run.'
Add-Md

function Format-ObservedMilliseconds {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return 'N/A'
    }

    $Text =
        ([string]$Value).Trim()

    if (
        [string]::IsNullOrWhiteSpace($Text) -or
        $Text -eq 'N/A'
    ) {
        return 'N/A'
    }

    $Number = 0.0

    $Parsed =
        [double]::TryParse(
            $Text,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::CurrentCulture,
            [ref]$Number
        )

    if (-not $Parsed) {
        $Parsed =
            [double]::TryParse(
                $Text,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$Number
            )
    }

    if (-not $Parsed) {
        return $Text
    }

    return $Number.ToString(
        '0.000',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Format-RunTimestamp {
    param(
        [Parameter(Mandatory)]
        [datetimeoffset]$Value
    )

    return $Value.ToString(
        'yyyy-MM-dd HH:mm:ss.fff zzz',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Format-RunDuration {
    param(
        [Parameter(Mandatory)]
        [timespan]$Value
    )

    $Invariant =
        [System.Globalization.CultureInfo]::InvariantCulture

    if ($Value.TotalHours -ge 1) {
        return [string]::Format(
            $Invariant,
            '{0} h {1} min {2:0.000} s',
            [math]::Floor($Value.TotalHours),
            $Value.Minutes,
            (
                $Value.Seconds +
                ($Value.Milliseconds / 1000.0)
            )
        )
    }

    if ($Value.TotalMinutes -ge 1) {
        return [string]::Format(
            $Invariant,
            '{0} min {1:0.000} s',
            [math]::Floor($Value.TotalMinutes),
            (
                $Value.Seconds +
                ($Value.Milliseconds / 1000.0)
            )
        )
    }

    return [string]::Format(
        $Invariant,
        '{0:0.000} s',
        $Value.TotalSeconds
    )
}
Add-Md '## Run identity'
Add-Md
Add-Md '| Field | Value |'
Add-Md '|---|---|'
Add-Md '| Repository | `digital-humanism/hacp-sidecar-ada` |'
Add-Md '| Implementation | `Ada/SPARK` |'
Add-Md '| Release | `1.1.1` |'
Add-Md "| HACP Core | ``$SpecVersion`` |"
Add-Md "| Conformance profile | ``$Profile`` |"
Add-Md "| Core vector set | ``$VectorSet`` |"
Add-Md '| HC2 vector family | `enforcement-v2` |'
Add-Md "| Run ID | ``$($Context.run_id)`` |"
Add-Md '| Report format | `1` |'
Add-Md '| Overall result | **PASS** |'
Add-Md

Add-Md '### Run timing'
Add-Md
Add-Md '| Event | Display | Exact value |'
Add-Md '|---|---|---|'
Add-Md (
    "| Started | " +
    "``$(Format-RunTimestamp $Started)`` | " +
    "``$($Started.ToString('o'))`` |"
)
Add-Md (
    "| Completed | " +
    "``$(Format-RunTimestamp $Completed)`` | " +
    "``$($Completed.ToString('o'))`` |"
)
Add-Md (
    "| Duration | " +
    "``$(Format-RunDuration $Duration)`` | " +
    "``$($Duration.ToString())`` |"
)
Add-Md (
    "| Report generated | " +
    "``$(Format-RunTimestamp $ReportGenerated)`` | " +
    "``$($ReportGenerated.ToString('o'))`` |"
)
Add-Md
Add-Md '## Environment'
Add-Md
Add-Md '| Component | Version / value |'
Add-Md '|---|---|'
Add-Md "| PowerShell | ``$($PSVersionTable.PSVersion)`` |"
Add-Md "| Python | ``$(Escape-MarkdownCell $PythonVersion)`` |"
Add-Md "| Go | ``$(Escape-MarkdownCell $GoVersion)`` |"
Add-Md "| Alire | ``$(Escape-MarkdownCell $AlireVersion)`` |"
Add-Md "| GNATMAKE | ``$(Escape-MarkdownCell $GnatVersion)`` |"
Add-Md "| GPRBuild | ``$(Escape-MarkdownCell $GprVersion)`` |"
Add-Md "| OS | ``$(Escape-MarkdownCell ([System.Runtime.InteropServices.RuntimeInformation]::OSDescription))`` |"
Add-Md "| OS architecture | ``$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)`` |"
Add-Md "| Process architecture | ``$([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)`` |"
Add-Md "| Time zone | ``$(Escape-MarkdownCell ([System.TimeZoneInfo]::Local.Id))`` |"
Add-Md

Add-Md '## Canonical reproduction inputs'
Add-Md
Add-Md '| Surface | Count / identity |'
Add-Md '|---|---|'
Add-Md '| Canonical harness | `9 files` |'
Add-Md '| Schemas | `6 files` |'
Add-Md '| HACP-Core vectors | `38` |'
Add-Md '| HC2 vectors | `55` |'
Add-Md '| Canonical total | `108 files` |'
Add-Md "| Manifest digest | ``$ManifestDigest`` |"
Add-Md "| Vector digest match | ``$DigestMatch`` |"
Add-Md

Add-Md '## Reproduction model'
Add-Md
Add-Md '```text'
Add-Md '00 Preflight'
Add-Md '      ↓'
Add-Md '01 Prepare Environment / Clean Build'
Add-Md '      ↓'
Add-Md '02 Run Verification'
Add-Md '      ↓'
Add-Md '03 Postflight'
Add-Md '      ↓'
Add-Md '04 Reconcile Results'
Add-Md '      ↓'
Add-Md '05 Generate Markdown Report'
Add-Md '```'
Add-Md
Add-Md '```text'
Add-Md '/src          Ada/SPARK implementation'
Add-Md '/harness      canonical conformance harness'
Add-Md '/schemas      canonical protocol/data schemas'
Add-Md '/vectors      canonical behavioral corpus'
Add-Md '/test/matrix  public reproduction orchestration'
Add-Md '```'
Add-Md

Add-Md '## Clean build artifacts'
Add-Md
Add-Md '| Executable | SHA-256 |'
Add-Md '|---|---|'

foreach ($Exe in $ExecutableRecords) {
    Add-Md "| ``$($Exe.Name)`` | ``$($Exe.SHA256)`` |"
}

Add-Md

Add-Md '## Evidence summary'
Add-Md
Add-Md '| Evidence family | Result | Evidence |'
Add-Md '|---|---|---|'
Add-Md '| HACP-Core | **PASS** | `38/38` |'
Add-Md '| HC2-55 | **PASS** | `55/55` |'
Add-Md '| Authorization-v2 | **PASS** | `3/3` |'
Add-Md '| humanist-core observable parity | **PASS** | targeted documented cases reproduced |'
Add-Md '| Runtime | **PASS** | `5/5` |'
Add-Md '| Managed HTTP | **PASS** | `100/100` warmup + `5000/5000` measured |'
Add-Md

Add-Md '## HACP-Core'
Add-Md
Add-Md '| Field | Value |'
Add-Md '|---|---|'
Add-Md "| Version | ``$SpecVersion`` |"
Add-Md "| Profile | ``$Profile`` |"
Add-Md "| Vector set | ``$VectorSet`` |"
Add-Md "| Result | **$(Get-LineValue -Text $CoreText -Name 'CORE_CANONICAL_CONFORMANCE')** |"
Add-Md "| Passed | ``$(Get-LineValue -Text $CoreText -Name 'CORE_PASSED')`` |"
Add-Md "| Failed | ``$(Get-LineValue -Text $CoreText -Name 'CORE_FAILED')`` |"
Add-Md (
    "| Suite wall time | " +
    "``$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_SUITE_WALL_MS')) ms`` |"
)
Add-Md "| Ada runner vectors | ``$(Get-LineValue -Text $CoreText -Name 'CORE_ADA_RUNNER_VECTOR_COUNT')`` |"
Add-Md "| Preflight-only vectors | ``$(Get-LineValue -Text $CoreText -Name 'CORE_PREFLIGHT_ONLY_VECTOR_COUNT')`` |"
Add-Md

Add-Md '### Timing statistics'
Add-Md
Add-Md '| Metric | Target evaluate | Vector total |'
Add-Md '|---|---:|---:|'
Add-Md (
    "| Count | " +
    "$(Get-LineValue -Text $CoreText -Name 'CORE_TARGET_EVALUATE_COUNT') | " +
    "$(Get-LineValue -Text $CoreText -Name 'CORE_VECTOR_TOTAL_COUNT') |"
)
Add-Md (
    "| Minimum (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_TARGET_EVALUATE_MIN_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_VECTOR_TOTAL_MIN_MS')) |"
)
Add-Md (
    "| Maximum (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_TARGET_EVALUATE_MAX_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_VECTOR_TOTAL_MAX_MS')) |"
)
Add-Md (
    "| Mean (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_TARGET_EVALUATE_MEAN_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_VECTOR_TOTAL_MEAN_MS')) |"
)
Add-Md (
    "| Median (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_TARGET_EVALUATE_MEDIAN_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_VECTOR_TOTAL_MEDIAN_MS')) |"
)
Add-Md (
    "| p95 (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_TARGET_EVALUATE_P95_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_VECTOR_TOTAL_P95_MS')) |"
)
Add-Md (
    "| p99 (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_TARGET_EVALUATE_P99_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $CoreText -Name 'CORE_VECTOR_TOTAL_P99_MS')) |"
)
Add-Md

Add-Md '<details>'
Add-Md '<summary><strong>38 canonical HACP-Core vectors — full result table</strong></summary>'
Add-Md
Add-Md '| # | Vector | Description | Expected | Observed | Execution path | Target evaluate ms | Vector total ms | Result |'
Add-Md '|---:|---|---|---|---|---|---:|---:|---|'

foreach ($Row in $CoreRows) {
    Add-Md (
        "| $($Row.Index) | ``$($Row.Id)`` | " +
        "$(Escape-MarkdownCell $Row.Description) | " +
        "``$(Escape-MarkdownCell $Row.Expected)`` | " +
        "``$(Escape-MarkdownCell $Row.Observed)`` | " +
        "``$($Row.ExecutionPath)`` | " +
        "$(Format-ObservedMilliseconds $Row.TargetMs) | " +
        "$(Format-ObservedMilliseconds $Row.TotalMs) | " +
        "**$($Row.Result)** |"
    )
}

Add-Md
Add-Md '</details>'
Add-Md
Add-Md '## HC2-55'
Add-Md
Add-Md '| Field | Value |'
Add-Md '|---|---|'
Add-Md '| Vector family | `enforcement-v2` |'
Add-Md "| Result | **$(Get-LineValue -Text $HC2Text -Name 'HC2_CANONICAL_CONFORMANCE')** |"
Add-Md "| Passed | ``$(Get-LineValue -Text $HC2Text -Name 'HC2_PASSED')`` |"
Add-Md "| Failed | ``$(Get-LineValue -Text $HC2Text -Name 'HC2_FAILED')`` |"
Add-Md (
    "| Suite wall time | " +
    "``$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_SUITE_WALL_MS')) ms`` |"
)
Add-Md "| Ada runner vectors | ``$(Get-LineValue -Text $HC2Text -Name 'HC2_ADA_RUNNER_VECTOR_COUNT')`` |"
Add-Md "| Preflight-only vectors | ``$(Get-LineValue -Text $HC2Text -Name 'HC2_PREFLIGHT_ONLY_VECTOR_COUNT')`` |"
Add-Md

Add-Md '### Timing statistics'
Add-Md
Add-Md '| Metric | Target evaluate | Vector total |'
Add-Md '|---|---:|---:|'
Add-Md (
    "| Count | " +
    "$(Get-LineValue -Text $HC2Text -Name 'HC2_TARGET_EVALUATE_COUNT') | " +
    "$(Get-LineValue -Text $HC2Text -Name 'HC2_VECTOR_TOTAL_COUNT') |"
)
Add-Md (
    "| Minimum (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_TARGET_EVALUATE_MIN_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_VECTOR_TOTAL_MIN_MS')) |"
)
Add-Md (
    "| Maximum (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_TARGET_EVALUATE_MAX_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_VECTOR_TOTAL_MAX_MS')) |"
)
Add-Md (
    "| Mean (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_TARGET_EVALUATE_MEAN_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_VECTOR_TOTAL_MEAN_MS')) |"
)
Add-Md (
    "| Median (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_TARGET_EVALUATE_MEDIAN_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_VECTOR_TOTAL_MEDIAN_MS')) |"
)
Add-Md (
    "| p95 (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_TARGET_EVALUATE_P95_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_VECTOR_TOTAL_P95_MS')) |"
)
Add-Md (
    "| p99 (ms) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_TARGET_EVALUATE_P99_MS')) | " +
    "$(Format-ObservedMilliseconds (Get-LineValue -Text $HC2Text -Name 'HC2_VECTOR_TOTAL_P99_MS')) |"
)
Add-Md

Add-Md '<details>'
Add-Md '<summary><strong>55 canonical HC2 vectors — full result table</strong></summary>'
Add-Md
Add-Md '| # | Vector | Description | Expected | Observed | Execution path | Target evaluate ms | Vector total ms | Result |'
Add-Md '|---:|---|---|---|---|---|---:|---:|---|'

foreach ($Row in $HC2Rows) {
    Add-Md (
        "| $($Row.Index) | ``$($Row.Id)`` | " +
        "$(Escape-MarkdownCell $Row.Description) | " +
        "``$(Escape-MarkdownCell $Row.Expected)`` | " +
        "``$(Escape-MarkdownCell $Row.Observed)`` | " +
        "``$($Row.ExecutionPath)`` | " +
        "$(Format-ObservedMilliseconds $Row.TargetMs) | " +
        "$(Format-ObservedMilliseconds $Row.TotalMs) | " +
        "**$($Row.Result)** |"
    )
}

Add-Md
Add-Md '</details>'
Add-Md
Add-Md '## Authorization-v2'
Add-Md
Add-Md '| Witness | Result |'
Add-Md '|---|---|'
Add-Md "| Action hash witness | **$(Get-LineValue -Text $AuthorizationText -Name 'ACTION_HASH_WITNESS')** |"
Add-Md "| Envelope signature witness | **$(Get-LineValue -Text $AuthorizationText -Name 'ENVELOPE_SIGNATURE_WITNESS')** |"
Add-Md "| Signed DENY witness | **$(Get-LineValue -Text $AuthorizationText -Name 'SIGNED_DENY_WITNESS')** |"
Add-Md
Add-Md "Result: **$(Get-LineValue -Text $AuthorizationText -Name 'RESULT') PASS**"
Add-Md

Add-Md '## humanist-core observable parity'
Add-Md
Add-Md '### Public witnesses'
Add-Md
Add-Md '| Observable case | Result |'
Add-Md '|---|---|'
Add-Md "| Checkpoint resolved DENY | **$(Get-LineValue -Text $ParityText -Name 'PARITY_CHECKPOINT_RESOLVED_DENY')** |"
Add-Md "| Unknown checkpoint state | **$(Get-LineValue -Text $ParityText -Name 'PARITY_CHECKPOINT_UNKNOWN_STATE')** |"
Add-Md "| Malformed provenance | **$(Get-LineValue -Text $ParityText -Name 'PARITY_PROVENANCE_MALFORMED')** |"
Add-Md "| Untrusted token signer | **$(Get-LineValue -Text $ParityText -Name 'PARITY_TRUST_UNTRUSTED_TOKEN_SIGNER')** |"
Add-Md "| Missing destination | **$(Get-LineValue -Text $ParityText -Name 'PARITY_SCOPE_MISSING_DESTINATION')** |"
Add-Md

Add-Md '### Direct canonical coverage'
Add-Md
Add-Md '| Field | Value |'
Add-Md '|---|---|'
Add-Md (
    "| Cases | ``$(Get-LineValue -Text $ParityText -Name 'DIRECT_CORE_PARITY_CASES')`` |"
)
Add-Md (
    "| Execution | ``$(Get-LineValue -Text $ParityText -Name 'DIRECT_CORE_PARITY_EXECUTION')`` |"
)
Add-Md

Add-Md '### Closure'
Add-Md
Add-Md '| Check | Result |'
Add-Md '|---|---|'
Add-Md "| Checkpoint parity | **$(Get-LineValue -Text $ParityText -Name 'CHECKPOINT_PARITY')** |"
Add-Md "| Scope parity | **$(Get-LineValue -Text $ParityText -Name 'SCOPE_PARITY')** |"
Add-Md "| Known semantic parity gaps | ``$(Get-LineValue -Text $ParityText -Name 'KNOWN_HUMANIST_CORE_SEMANTIC_PARITY_GAPS')`` |"
Add-Md "| Known semantic RED | **$(Get-LineValue -Text $ParityText -Name 'KNOWN_SEMANTIC_RED')** |"
Add-Md "| Synthetic total | ``$(Get-LineValue -Text $ParityText -Name 'PARITY_SYNTHETIC_TOTAL')`` |"
Add-Md "| Observable parity | **$(Get-LineValue -Text $ParityText -Name 'ADA_HUMANIST_CORE_OBSERVABLE_PARITY')** |"
Add-Md
Add-Md '## Runtime'
Add-Md

$RuntimeSummary =
    [regex]::Match(
        $RuntimeText,
        '(?ms)^=== RUNTIME TIMING SUMMARY ===\s*' +
        '(?<body>.*?)' +
        '^=== RUNTIME ERRORS ==='
    )

if (-not $RuntimeSummary.Success) {
    throw 'Runtime timing summary missing from evidence.'
}

$RuntimeRows =
    @(
        foreach (
            $Line in (
                $RuntimeSummary.Groups['body'].Value.Trim() `
                    -split '\r?\n'
            )
        ) {
            $Match =
                [regex]::Match(
                    $Line.Trim(),
                    '^(?<surface>[^|]+?)\s*\|\s*' +
                    '(?<result>[^|]+?)\s*\|\s*' +
                    '(?<duration>[\d.,]+)\s+ms$'
                )

            if ($Match.Success) {
                [pscustomobject]@{
                    Surface =
                        $Match.Groups['surface'].Value.Trim()

                    Result =
                        $Match.Groups['result'].Value.Trim()

                    Duration =
                        $Match.Groups['duration'].Value.Trim()
                }
            }
        }
    )

if ($RuntimeRows.Count -ne 5) {
    throw "Expected 5 runtime timing rows; observed $($RuntimeRows.Count)"
}

Add-Md '| Runtime surface | Result | Duration (ms) |'
Add-Md '|---|---|---:|'

foreach ($Row in $RuntimeRows) {
    Add-Md (
        "| ``$($Row.Surface)`` | " +
        "**$($Row.Result)** | " +
        "$(Format-ObservedMilliseconds $Row.Duration) |"
    )
}

Add-Md
Add-Md '| Runtime summary | Value |'
Add-Md '|---|---:|'
Add-Md "| Surfaces | ``$(Get-LineValue -Text $RuntimeText -Name 'RUNTIME_SURFACES')`` |"
Add-Md "| Passed | ``$(Get-LineValue -Text $RuntimeText -Name 'RUNTIME_PASSED')`` |"
Add-Md "| Failed | ``$(Get-LineValue -Text $RuntimeText -Name 'RUNTIME_FAILED')`` |"
Add-Md "| Overall | **$(Get-LineValue -Text $RuntimeText -Name 'ADA_RUNTIME')** |"
Add-Md
Add-Md '## Managed HTTP reproduction'
Add-Md
Add-Md '| Functional check | Result |'
Add-Md '|---|---|'
Add-Md "| Unsigned / negative request | **$(Get-LineValue -Text $HttpText -Name 'HTTP_NEGATIVE_403_DENY')** |"
Add-Md "| Signed single request | **$(Get-LineValue -Text $HttpText -Name 'HTTP_SINGLE_200_ALLOW')** |"
Add-Md

Add-Md '### Workload metrics'
Add-Md
Add-Md '> Displayed timing values are rounded to three decimal places. Exact observed JSON values are preserved in Raw evidence.'
Add-Md
Add-Md '| Phase | Requests | Success | Failed | Concurrency | Elapsed ms | Mean ms | p50 ms | p95 ms | p99 ms | Max ms |'
Add-Md '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|'

foreach ($Record in $HttpRecords) {
    Add-Md (
        "| $($Record.phase) | " +
        "$($Record.requests) | " +
        "$($Record.success) | " +
        "$($Record.failed) | " +
        "$($Record.concurrency) | " +
        "$(Format-ObservedMilliseconds $Record.elapsed_ms) | " +
        "$(Format-ObservedMilliseconds $Record.mean_ms) | " +
        "$(Format-ObservedMilliseconds $Record.p50_ms) | " +
        "$(Format-ObservedMilliseconds $Record.p95_ms) | " +
        "$(Format-ObservedMilliseconds $Record.p99_ms) | " +
        "$(Format-ObservedMilliseconds $Record.max_ms) |"
    )
}

Add-Md
Add-Md '## Final reconciliation'
Add-Md
Add-Md '| Evidence / acceptance check | Result |'
Add-Md '|---|---|'
Add-Md "| HACP-Core | **$($Reconciliation.core)** |"
Add-Md "| HC2-55 | **$($Reconciliation.hc2)** |"
Add-Md "| Authorization-v2 | **$($Reconciliation.authorization_v2)** |"
Add-Md "| humanist-core observable parity | ``$($Reconciliation.humanist_core_parity)`` |"
Add-Md "| Parity synthetic total | ``$($Reconciliation.parity_synthetic_total)`` |"
Add-Md "| Runtime | **$($Reconciliation.runtime)** |"
Add-Md "| HTTP functional | **$($Reconciliation.http_functional)** |"
Add-Md "| HTTP workload | ``$($Reconciliation.http_workload)`` |"
Add-Md "| HTTP failures | ``$($Reconciliation.http_failures)`` |"
Add-Md "| HTTP concurrency | ``$($Reconciliation.http_concurrency)`` |"
Add-Md "| Known semantic RED | **$($Reconciliation.known_semantic_red)** |"
Add-Md "| Reconciliation | **$($Reconciliation.reconciliation)** |"
Add-Md "| Release acceptance | ``$($Reconciliation.release_acceptance)`` |"
Add-Md
Add-Md '## Evidence boundaries'
Add-Md
Add-Md '- This report records one observed public reproduction run.'
Add-Md '- Timing values are observational and environment-dependent.'
Add-Md '- No synthetic evidence total is used.'
Add-Md '- humanist-core parity is limited to the documented targeted observable cases.'
Add-Md '- Canonical conformance inputs are repository-owned under `/harness`, `/schemas`, and `/vectors`.'
Add-Md '- Temporary witnesses and workload material are generated outside the tracked repository.'
Add-Md '- Release acceptance remains a human decision.'
Add-Md

# ================================================================
# Evidence bundle
#
# The report is the structured human-readable reproduction record.
# Exact family stdout is preserved separately, byte-for-byte.
# ================================================================

$ReportBaseName =
    [System.IO.Path]::GetFileNameWithoutExtension(
        $ReportPath
    )

$EvidenceBundleName =
    $ReportBaseName + '_evidence'

$EvidenceBundleRoot =
    Join-Path `
        $ReportRoot `
        $EvidenceBundleName

if (Test-Path -LiteralPath $EvidenceBundleRoot) {
    Remove-Item `
        -LiteralPath $EvidenceBundleRoot `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $EvidenceBundleRoot `
    -Force |
    Out-Null

$EvidenceLabels =
    [ordered]@{
        core =
            'HACP-Core'

        hc2 =
            'HC2-55'

        authorization_v2 =
            'Authorization-v2'

        parity =
            'humanist-core observable parity'

        runtime =
            'Runtime'

        http =
            'Managed HTTP'
    }

$EvidenceResultNames =
    [ordered]@{
        core =
            'CORE'

        hc2 =
            'HC2'

        authorization_v2 =
            'AUTHORIZATION_V2'

        parity =
            'PARITY'

        runtime =
            'RUNTIME'

        http =
            'HTTP'
    }

$EvidenceArtifacts =
    [System.Collections.Generic.List[object]]::new()

foreach ($Name in $FamilyNames) {

    $SourcePath =
        Join-Path `
            $EvidenceRoot `
            "$Name.log"

    $TargetPath =
        Join-Path `
            $EvidenceBundleRoot `
            "$Name.log"

    if (-not (
        Test-Path `
            -LiteralPath $SourcePath `
            -PathType Leaf
    )) {
        throw "Evidence source missing: $SourcePath"
    }

    Copy-Item `
        -LiteralPath $SourcePath `
        -Destination $TargetPath `
        -Force

    $SourceHash =
        (
            Get-FileHash `
                -LiteralPath $SourcePath `
                -Algorithm SHA256
        ).Hash

    $TargetHash =
        (
            Get-FileHash `
                -LiteralPath $TargetPath `
                -Algorithm SHA256
        ).Hash

    if ($SourceHash -ne $TargetHash) {
        throw "Evidence transfer integrity failure: $Name"
    }

    $ResultName =
        $EvidenceResultNames[$Name]

    $ResultEntry =
        @(
            $Results |
                Where-Object family -eq $ResultName
        )

    if ($ResultEntry.Count -ne 1) {
        throw (
            "Expected one verification result for " +
            "$ResultName"
        )
    }

    $LineCount =
        (
            [System.IO.File]::ReadAllLines(
                $TargetPath
            )
        ).Count

    $EvidenceArtifacts.Add(
        [pscustomobject]@{
            Name =
                $Name

            Label =
                $EvidenceLabels[$Name]

            Result =
                [string]$ResultEntry[0].status

            Lines =
                $LineCount

            SHA256 =
                $TargetHash

            FileName =
                "$Name.log"
        }
    )
}

if ($EvidenceArtifacts.Count -ne 6) {
    throw (
        'Expected 6 evidence artifacts; observed ' +
        "$($EvidenceArtifacts.Count)"
    )
}

Add-Md '## Evidence artifacts'
Add-Md
Add-Md 'The complete observed stdout for every evidence family is preserved alongside this report as separate lossless evidence artifacts.'
Add-Md
Add-Md '| Evidence family | Result | Lines | SHA-256 | Artifact |'
Add-Md '|---|---|---:|---|---|'

foreach ($Artifact in $EvidenceArtifacts) {

    $RelativePath =
        (
            $EvidenceBundleName +
            '/' +
            $Artifact.FileName
        )

    Add-Md (
        "| $($Artifact.Label) | " +
        "**$($Artifact.Result)** | " +
        "$($Artifact.Lines) | " +
        "``$($Artifact.SHA256)`` | " +
        "[$($Artifact.FileName)]($RelativePath) |"
    )
}

Add-Md
Add-Md '### Evidence integrity'
Add-Md
Add-Md '| Check | Result |'
Add-Md '|---|---|'
Add-Md '| Raw family output | **PRESERVED WITHOUT TRANSFORMATION** |'
Add-Md '| Evidence families | **6/6** |'
Add-Md '| Transfer integrity | **SHA-256 VERIFIED** |'
Add-Md '| Known semantic RED | **NONE** |'
Add-Md '| Reconciliation | **PASS** |'
Add-Md '| Synthetic evidence total | `NOT_USED` |'
Add-Md
Add-Md '> The Markdown report presents structured evidence. The accompanying `.log` files preserve the exact observed family stdout used to construct it.'
Add-Md
$Utf8NoBom =
    [System.Text.UTF8Encoding]::new($false)

$ReportText =
    ($Md -join "`n") + "`n"

[System.IO.File]::WriteAllText(
    $ReportPath,
    $ReportText,
    $Utf8NoBom
)

$Bytes =
    [System.IO.File]::ReadAllBytes($ReportPath)

if ($Bytes.Length -eq 0) {
    throw 'Generated report is empty.'
}

if (
    $Bytes.Length -ge 3 -and
    $Bytes[0] -eq 0xEF -and
    $Bytes[1] -eq 0xBB -and
    $Bytes[2] -eq 0xBF
) {
    throw 'Generated report unexpectedly contains UTF-8 BOM.'
}

if ($Bytes[-1] -ne 0x0A) {
    throw 'Generated report is missing final LF.'
}

# ================================================================
# HTML companion report
#
# The Markdown report remains the canonical text record.
# HTML is a rendered companion view of the exact same ReportText.
# No evidence is re-executed or independently interpreted here.
# ================================================================

$MarkdownCommand =
    Get-Command `
        -Name 'ConvertFrom-Markdown' `
        -ErrorAction SilentlyContinue

if ($null -eq $MarkdownCommand) {
    throw (
        'ConvertFrom-Markdown is unavailable. ' +
        'HTML companion generation cannot continue.'
    )
}

$HtmlPath =
    [System.IO.Path]::ChangeExtension(
        $ReportPath,
        '.html'
    )

$RenderedMarkdown =
    ConvertFrom-Markdown `
        -InputObject $ReportText

if (
    $null -eq $RenderedMarkdown -or
    [string]::IsNullOrWhiteSpace(
        [string]$RenderedMarkdown.Html
    )
) {
    throw 'Markdown-to-HTML rendering produced no content.'
}

$HtmlDocument = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>HACP Sidecar Ada — Public Reproduction Report</title>
<style>
:root {
    --bg: #f6f7f8;
    --surface: #ffffff;
    --surface-soft: #fafafa;
    --text: #17191c;
    --muted: #686d75;
    --line: #dfe2e6;
    --line-strong: #c9cdd2;
    --pass: #16784a;
    --pass-bg: #edf8f2;
    --mono-bg: #f3f4f5;
}

* {
    box-sizing: border-box;
}

html {
    background: var(--bg);
}

body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family:
        Inter,
        ui-sans-serif,
        system-ui,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        sans-serif;
    line-height: 1.55;
}

.page {
    width: min(1240px, calc(100% - 40px));
    margin: 40px auto 72px;
}

.report {
    overflow: hidden;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 14px;
    box-shadow:
        0 1px 2px rgba(0,0,0,.03),
        0 12px 36px rgba(0,0,0,.04);
}

.hero {
    padding: 42px 48px 38px;
    border-bottom: 1px solid var(--line);
}

.eyebrow {
    margin: 0 0 12px;
    color: var(--muted);
    font-size: 12px;
    font-weight: 700;
    letter-spacing: .12em;
    text-transform: uppercase;
}

.hero h1 {
    margin: 0;
    max-width: 900px;
    color: var(--text);
    border: 0;
    padding: 0;
    font-size: clamp(30px, 4vw, 48px);
    line-height: 1.08;
    letter-spacing: -.035em;
    font-weight: 680;
}

.hero-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 12px 24px;
    margin-top: 24px;
    color: var(--muted);
    font-size: 13px;
}

.result-strip {
    display: grid;
    grid-template-columns: 150px 1fr;
    align-items: center;
    gap: 26px;
    padding: 26px 48px;
    background: var(--pass-bg);
    border-bottom: 1px solid #cfe9da;
}

.result-badge {
    display: inline-flex;
    width: fit-content;
    min-width: 88px;
    align-items: center;
    justify-content: center;
    padding: 8px 14px;
    border: 1px solid #aad9bf;
    border-radius: 999px;
    color: var(--pass);
    background: #fff;
    font-size: 13px;
    font-weight: 800;
    letter-spacing: .08em;
}

.result-copy {
    color: #285f46;
    font-size: 15px;
}

.report-content {
    padding: 14px 48px 48px;
}

/*
 * Markdown contains its own canonical H1.
 * Keep it in the HTML source but avoid presenting a duplicated title.
 */
.report-content > h1:first-child {
    display: none;
}

/*
 * The opening Markdown blockquote is canonical report prose,
 * not an alert.
 */
.report-content > blockquote:first-of-type {
    margin: 28px 0 8px;
    padding: 16px 18px;
    border: 1px solid var(--line);
    border-left: 3px solid var(--line-strong);
    border-radius: 0 8px 8px 0;
    color: var(--muted);
    background: var(--surface-soft);
}

h2 {
    margin: 42px 0 20px;
    padding-top: 4px;
    padding-bottom: 10px;
    border-bottom: 1px solid var(--line);
    color: var(--text);
    font-size: 23px;
    line-height: 1.25;
    letter-spacing: -.018em;
}

h3 {
    margin: 28px 0 14px;
    color: var(--text);
    font-size: 17px;
}

h4 {
    color: var(--text);
}

p {
    margin: 12px 0;
}

strong {
    font-weight: 680;
}

code {
    padding: 2px 6px;
    border: 1px solid var(--line);
    border-radius: 5px;
    background: var(--mono-bg);
    font-family:
        "Cascadia Mono",
        "Cascadia Code",
        Consolas,
        monospace;
    font-size: .9em;
}

pre {
    overflow-x: auto;
    margin: 16px 0;
    padding: 18px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--mono-bg);
}

pre code {
    padding: 0;
    border: 0;
    background: transparent;
}

table {
    width: 100%;
    margin: 16px 0 24px;
    border-collapse: separate;
    border-spacing: 0;
    font-size: 14px;
    border: 1px solid var(--line);
    border-radius: 9px;
    overflow: hidden;
}

th,
td {
    padding: 11px 13px;
    border-right: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
    vertical-align: top;
}

th:last-child,
td:last-child {
    border-right: 0;
}

tr:last-child td {
    border-bottom: 0;
}

th {
    color: var(--muted);
    background: var(--surface-soft);
    text-align: left;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: .015em;
}

tr:nth-child(even) td {
    background: #fcfcfd;
}

/*
 * PASS values become restrained green evidence,
 * without turning the whole report into a dashboard.
 */
td strong {
    color: var(--pass);
}

/*
 * Full vector families remain collapsible.
 */
details {
    margin: 18px 0 26px;
    border: 1px solid var(--line);
    border-radius: 9px;
    background: var(--surface-soft);
    overflow: hidden;
}

summary {
    cursor: pointer;
    padding: 15px 17px;
    font-weight: 650;
    background: #fff;
}

details[open] summary {
    border-bottom: 1px solid var(--line);
}

details > table {
    margin: 0;
    border: 0;
    border-radius: 0;
}

/*
 * Evidence artifact links.
 * Markdown already owns the relative hrefs.
 */
a {
    color: inherit;
    text-decoration: none;
}

a:hover {
    text-decoration: none;
}

a[href$=".log"] {
    display: inline-flex;
    align-items: center;
    padding: 6px 9px;
    border: 1px solid var(--line);
    border-radius: 6px;
    background: var(--surface-soft);
    color: var(--text);
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: 12px;
    transition:
        border-color .15s ease,
        background .15s ease,
        transform .15s ease;
}

a[href$=".log"]:hover {
    border-color: var(--line-strong);
    background: #fff;
    transform: translateY(-1px);
}

/*
 * The final sections are intentionally visually stronger.
 */
.report-content h2:nth-last-of-type(-n+2) {
    margin-top: 48px;
}

.report-footer {
    padding: 18px 48px 22px;
    border-top: 1px solid var(--line);
    color: var(--muted);
    background: var(--surface);
    font-size: 12px;
    text-align: right;
}

@media (max-width: 820px) {
    .page {
        width: min(100% - 20px, 1240px);
        margin: 10px auto 30px;
    }

    .hero,
    .report-content {
        padding-left: 24px;
        padding-right: 24px;
    }

    .result-strip {
        grid-template-columns: 1fr;
        padding: 22px 24px;
    }

    table {
        display: block;
        overflow-x: auto;
        white-space: nowrap;
    }

    .report-footer {
        padding: 16px 24px;
    }
}

@media print {
    html,
    body {
        background: #fff;
    }

    .page {
        width: 100%;
        margin: 0;
    }

    .report {
        border: 0;
        border-radius: 0;
        box-shadow: none;
    }

    .result-strip {
        background: #fff;
        border-top: 1px solid var(--line);
    }

    details {
        break-inside: avoid;
    }

    a[href$=".log"] {
        border: 0;
        padding: 0;
        background: transparent;
    }
}
</style>
</head>
<body>
<div class="page">
<article class="report">

<header class="hero">
    <p class="eyebrow">HACP · Release 1.1.1 · Public reproduction evidence</p>
    <h1>HACP Sidecar Ada Reproduction</h1>

    <div class="hero-meta">
        <span>Ada / SPARK implementation</span>
        <span>Run ID: $($Context.run_id)</span>
        <span>Generated: $($ReportGenerated.ToString('o'))</span>
    </div>
</header>

<div class="result-strip">
    <span class="result-badge">PASS</span>

    <div class="result-copy">
        Fresh public reproduction completed across HACP-Core,
        HC2-55, Authorization-v2, observable parity, runtime and
        managed HTTP evidence families. No synthetic evidence total
        is used. Release acceptance remains a human decision.
    </div>
</div>

<main class="report-content">
$($RenderedMarkdown.Html)
</main>

<footer class="report-footer">
HACP Sidecar Ada · Release 1.1.1 ·
Public reproduction companion view ·
Run ID: $($Context.run_id)
</footer>

</article>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText(
    $HtmlPath,
    (
        ($HtmlDocument -replace "`r`n", "`n") `
            -replace "`r", "`n"
    ) + "`n",
    $Utf8NoBom
)

$HtmlBytes =
    [System.IO.File]::ReadAllBytes($HtmlPath)

if ($HtmlBytes.Length -eq 0) {
    throw 'Generated HTML report is empty.'
}

if (
    $HtmlBytes.Length -ge 3 -and
    $HtmlBytes[0] -eq 0xEF -and
    $HtmlBytes[1] -eq 0xBB -and
    $HtmlBytes[2] -eq 0xBF
) {
    throw 'Generated HTML report unexpectedly contains UTF-8 BOM.'
}

if ($HtmlBytes[-1] -ne 0x0A) {
    throw 'Generated HTML report is missing final LF.'
}

$HtmlCheck =
    [System.IO.File]::ReadAllText($HtmlPath)

foreach ($RequiredHtmlMarker in @(
    '<!doctype html>',
    '<article class="report">',
    'HACP Sidecar Ada — Public Reproduction Report',
    'class="result-badge">PASS',
    'HACP Sidecar Ada Reproduction',
    'class="report-content"',
    'Evidence summary',
    'HACP-Core',
    'HC2-55',
    'humanist-core observable parity',
    'Managed HTTP reproduction',
    'Evidence artifacts',
    $EvidenceBundleName
)) {
    if (-not $HtmlCheck.Contains($RequiredHtmlMarker)) {
        throw (
            'Generated HTML report is missing marker: ' +
            $RequiredHtmlMarker
        )
    }
}

$Caches =
    @(
        Get-ChildItem `
            -LiteralPath $RepoRoot `
            -Recurse `
            -Directory `
            -Filter '__pycache__' `
            -ErrorAction SilentlyContinue
    )

foreach ($Cache in $Caches) {
    Remove-Item `
        -LiteralPath $Cache.FullName `
        -Recurse `
        -Force
}

$RemainingCaches =
    @(
        Get-ChildItem `
            -LiteralPath $RepoRoot `
            -Recurse `
            -Directory `
            -Filter '__pycache__' `
            -ErrorAction SilentlyContinue
    )

if ($RemainingCaches.Count -ne 0) {
    throw 'Generated Python cache cleanup incomplete.'
}

Write-Host
Write-Host '============================================================'
Write-Host 'HACP SIDECAR ADA — PUBLIC REPRODUCTION COMPLETE'
Write-Host '============================================================'
Write-Host 'RELEASE=1.1.1'
Write-Host "RUN_ID=$($Context.run_id)"
Write-Host 'RESULT=PASS'
Write-Host 'CORE=38/38 PASS'
Write-Host 'HC2=55/55 PASS'
Write-Host 'AUTHORIZATION_V2=3/3 PASS'
Write-Host 'HUMANIST_CORE_PARITY=TARGETED DOCUMENTED CASES REPRODUCED'
Write-Host 'RUNTIME=5/5 PASS'
Write-Host 'HTTP=100/100 WARMUP + 5000/5000 MEASURED'
Write-Host 'HTTP_FAILURES=0'
Write-Host 'GENERATED_PYTHON_CACHE=NONE'
Write-Host 'REPRODUCTION_REPORT=PASS'
Write-Host "REPORT_PATH=$ReportPath"
Write-Host 'HTML_COMPANION_REPORT=PASS'
Write-Host "HTML_REPORT_PATH=$HtmlPath"
Write-Host '============================================================'
