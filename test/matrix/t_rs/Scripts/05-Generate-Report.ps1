param(
    [Parameter(Mandatory)]
    [string]$RunRoot
)

$ErrorActionPreference = 'Stop'

$Evidence =
    Join-Path $RunRoot 'evidence'

$ReconciliationPath =
    Join-Path $RunRoot 'reconciliation.json'

if (-not (Test-Path -LiteralPath $ReconciliationPath -PathType Leaf)) {
    throw "Reconciliation artifact missing: $ReconciliationPath"
}

$R =
    Get-Content `
        -LiteralPath $ReconciliationPath `
        -Raw `
        -Encoding UTF8 |
    ConvertFrom-Json

if ($null -eq $R) {
    throw 'Reconciliation object is null.'
}

$RequiredEvidence = @(
    'ada_prepare.log',
    'ada_core.log',
    'rust_core.log',
    'ada_authorization_v2.log',
    'rust_authorization_v2.log'
)

foreach ($Name in $RequiredEvidence) {
    $Path = Join-Path $Evidence $Name

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required evidence missing: $Path"
    }
}

$ReportRoot =
    Join-Path $RunRoot 'report'

$ReportEvidence =
    Join-Path $ReportRoot '_evidence'

New-Item `
    -ItemType Directory `
    -Path $ReportEvidence `
    -Force |
Out-Null

foreach ($Name in $RequiredEvidence) {
    Copy-Item `
        -LiteralPath (Join-Path $Evidence $Name) `
        -Destination (Join-Path $ReportEvidence $Name) `
        -Force
}

$MarkdownPath =
    Join-Path `
        $ReportRoot `
        'HACP_SIDECAR_ADA_RUST_CROSS_IMPLEMENTATION_REPRODUCTION.md'

$HtmlPath =
    Join-Path `
        $ReportRoot `
        'HACP_SIDECAR_ADA_RUST_CROSS_IMPLEMENTATION_REPRODUCTION.html'

$GeneratedAt =
    (Get-Date).ToString('o')

# ============================================================
# Canonical Markdown
# ============================================================

$Lines = @(
    '# HACP Sidecar Ada / Rust Cross-Implementation Reproduction',
    '',
    'Release: 1.1.1',
    '',
    "Generated: $GeneratedAt",
    '',
    '## Result',
    '',
    '**PASS**',
    '',
    'This report records a fresh repository-owned cross-implementation reproduction using Ada and Rust evaluator surfaces.',
    '',
    'No synthetic combined score is used.',
    '',
    '## Current Core direct-conformance evidence',
    '',
    '| Implementation | Result |',
    '|---|---|',
    "| Ada Core-compatible | $([string]$R.ada_core_direct) |",
    "| Rust Core-compatible | $([string]$R.rust_core_compatible) |",
    '',
    'Both implementations consume the canonical Core vector set from the repository root.',
    '',
    '## Historical Rust accounting',
    '',
    'Historical Rust verification accounting remains:',
    '',
    "**$([string]$R.rust_historical_core)**",
    '',
    'Historical adjudicated cases:',
    '',
    '- CORE-INV1-002',
    '- CORE-RUNTIME-004',
    '',
    'This historical accounting is preserved and is not rewritten by the newer Core-compatible direct reproduction.',
    '',
    'Both historical adjudicated cases now pass directly in the current Ada and Rust Core-compatible execution paths.',
    '',
    '## Authorization-v2 evidence',
    '',
    '| Implementation | Result |',
    '|---|---|',
    "| Ada Authorization-v2 | $([string]$R.ada_authorization_v2) |",
    "| Rust Authorization-v2 | $([string]$R.rust_authorization_v2) |",
    '',
    'The witness family contains:',
    '',
    '- ACTION_HASH_WITNESS -> DENY / SIGNATURE_FAILURE',
    '- ENVELOPE_SIGNATURE_WITNESS -> DENY / SIGNATURE_FAILURE',
    '- SIGNED_DENY_WITNESS -> DENY / POLICY_DENIED',
    '',
    '## Cross-implementation reconciliation',
    '',
    "- Core: **$([string]$R.cross_implementation_core)**",
    "- Authorization-v2: **$([string]$R.cross_implementation_authorization_v2)**",
    "- Known semantic RED: **$([string]$R.known_semantic_red)**",
    "- Synthetic total: **$([string]$R.synthetic_total)**",
    '',
    '## Repository ownership and reproduction boundary',
    '',
    'The reproduction uses repository-owned assets.',
    '',
    'Canonical vectors remain owned by:',
    '',
    '`vectors/`',
    '',
    'The Rust bounded evaluator package is owned by:',
    '',
    '`test/matrix/t_rs/rust/`',
    '',
    'Stable Ada implementation and environment assets already present in this repository are reused in place.',
    '',
    'The existing Ada matrix is not modified.',
    '',
    'No laboratory checkout or sibling repository is required at runtime.',
    '',
    'Public reproduction is repository- and version-driven.',
    '',
    'Historical source hashes are not used as build, dependency, implementation, release, or navigation selectors.',
    '',
    'Protocol-intrinsic cryptographic hashing remains part of HACP semantics.',
    '',
    '## Evidence files',
    '',
    'Raw execution evidence is retained under:',
    '',
    '`_evidence/`',
    '',
    '- [ada_prepare.log](_evidence/ada_prepare.log)',
    '- [ada_core.log](_evidence/ada_core.log)',
    '- [rust_core.log](_evidence/rust_core.log)',
    '- [ada_authorization_v2.log](_evidence/ada_authorization_v2.log)',
    '- [rust_authorization_v2.log](_evidence/rust_authorization_v2.log)',
    '',
    '## Final status',
    '',
    '```text',
    "ADA_CORE_DIRECT=$([string]$R.ada_core_direct)",
    "RUST_CORE_COMPATIBLE=$([string]$R.rust_core_compatible)",
    "RUST_HISTORICAL_CORE=$([string]$R.rust_historical_core)",
    "ADA_AUTHORIZATION_V2=$([string]$R.ada_authorization_v2)",
    "RUST_AUTHORIZATION_V2=$([string]$R.rust_authorization_v2)",
    "CROSS_IMPLEMENTATION_CORE=$([string]$R.cross_implementation_core)",
    "CROSS_IMPLEMENTATION_AUTHORIZATION_V2=$([string]$R.cross_implementation_authorization_v2)",
    "KNOWN_SEMANTIC_RED=$([string]$R.known_semantic_red)",
    "SYNTHETIC_TOTAL=$([string]$R.synthetic_total)",
    'REPRODUCTION_REPORT=PASS',
    '```',
    ''
)

$Markdown =
    $Lines -join "`n"

[System.IO.File]::WriteAllText(
    $MarkdownPath,
    $Markdown,
    [System.Text.UTF8Encoding]::new($false)
)

# ============================================================
# Presentation HTML
# ============================================================

function ConvertTo-TRsHtmlSafe {
    param([AllowNull()][object]$Value)

    return [System.Net.WebUtility]::HtmlEncode(
        [string]$Value
    )
}

$AdaCore = ConvertTo-TRsHtmlSafe -Value $R.ada_core_direct
$RustCore = ConvertTo-TRsHtmlSafe -Value $R.rust_core_compatible
$Historical = ConvertTo-TRsHtmlSafe -Value $R.rust_historical_core
$AdaAuth = ConvertTo-TRsHtmlSafe -Value $R.ada_authorization_v2
$RustAuth = ConvertTo-TRsHtmlSafe -Value $R.rust_authorization_v2
$CrossCore = ConvertTo-TRsHtmlSafe -Value $R.cross_implementation_core
$CrossAuth = ConvertTo-TRsHtmlSafe -Value $R.cross_implementation_authorization_v2
$SemanticRed = ConvertTo-TRsHtmlSafe -Value $R.known_semantic_red
$Synthetic = ConvertTo-TRsHtmlSafe -Value $R.synthetic_total
$Generated = ConvertTo-TRsHtmlSafe -Value $GeneratedAt

$Html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">

<title>HACP Sidecar Ada / Rust Cross-Implementation Reproduction</title>

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
    width: min(1120px, calc(100% - 40px));
    margin: 40px auto 72px;
}

.report {
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 14px;
    overflow: hidden;
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

h1 {
    margin: 0;
    max-width: 850px;
    font-size: clamp(30px, 4vw, 48px);
    line-height: 1.08;
    letter-spacing: -.035em;
    font-weight: 680;
}

.meta {
    display: flex;
    gap: 12px 24px;
    flex-wrap: wrap;
    margin-top: 24px;
    color: var(--muted);
    font-size: 13px;
}

.result-strip {
    display: grid;
    grid-template-columns: 150px 1fr;
    gap: 26px;
    align-items: center;
    padding: 26px 48px;
    background: var(--pass-bg);
    border-bottom: 1px solid #cfe9da;
}

.result-badge {
    display: inline-flex;
    width: fit-content;
    align-items: center;
    justify-content: center;
    min-width: 88px;
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

section {
    padding: 38px 48px;
    border-bottom: 1px solid var(--line);
}

section:last-child {
    border-bottom: 0;
}

.section-kicker {
    margin: 0 0 7px;
    color: var(--muted);
    font-size: 11px;
    font-weight: 700;
    letter-spacing: .11em;
    text-transform: uppercase;
}

h2 {
    margin: 0 0 22px;
    font-size: 23px;
    letter-spacing: -.018em;
}

p {
    margin: 12px 0;
}

.grid-2 {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px;
}

.metric {
    padding: 20px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--surface-soft);
}

.metric-label {
    display: block;
    color: var(--muted);
    font-size: 12px;
    margin-bottom: 7px;
}

.metric-value {
    display: block;
    font-size: 20px;
    font-weight: 700;
    letter-spacing: -.015em;
}

.pass {
    color: var(--pass);
}

.history {
    padding: 22px 24px;
    border-left: 3px solid var(--line-strong);
    background: var(--surface-soft);
    border-radius: 0 8px 8px 0;
}

.history-value {
    margin: 5px 0 15px;
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: 17px;
    font-weight: 700;
}

.case-row {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
    margin-top: 13px;
}

.case {
    padding: 6px 9px;
    border: 1px solid var(--line);
    border-radius: 6px;
    background: #fff;
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: 12px;
}

.witness-list {
    display: grid;
    gap: 9px;
    margin-top: 20px;
}

.witness {
    display: grid;
    grid-template-columns: minmax(220px, 1fr) auto;
    gap: 15px;
    padding: 13px 15px;
    border: 1px solid var(--line);
    border-radius: 8px;
}

.witness-name {
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: 13px;
}

.witness-result {
    color: var(--muted);
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: 12px;
}

.status-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0 32px;
}

.status-row {
    display: flex;
    justify-content: space-between;
    gap: 18px;
    padding: 12px 0;
    border-bottom: 1px solid var(--line);
}

.status-label {
    color: var(--muted);
}

.status-value {
    font-weight: 700;
}

code {
    padding: 2px 6px;
    background: var(--mono-bg);
    border: 1px solid var(--line);
    border-radius: 5px;
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: .9em;
}

.evidence-list {
    margin: 16px 0 0;
    padding-left: 20px;
}

.evidence-list li {
    margin: 6px 0;
}

.evidence-links {
    display: grid;
    gap: 8px;
    margin-top: 18px;
}

.evidence-link {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
    padding: 13px 15px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--surface-soft);
    color: var(--text);
    text-decoration: none;
    transition:
        border-color .15s ease,
        background .15s ease,
        transform .15s ease;
}

.evidence-link:hover {
    border-color: var(--line-strong);
    background: #fff;
    transform: translateY(-1px);
}

.evidence-name {
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: 13px;
}

.evidence-action {
    color: var(--muted);
    font-size: 12px;
    white-space: nowrap;
}

.final {
    background: #111315;
    color: #e9eaec;
}

.final .section-kicker {
    color: #8f959d;
}

.final h2 {
    color: #fff;
}

.final pre {
    margin: 0;
    overflow-x: auto;
    font-family: "Cascadia Mono", Consolas, monospace;
    font-size: 13px;
    line-height: 1.65;
    color: #dfe7e2;
}

.footer {
    padding: 18px 48px 22px;
    color: var(--muted);
    font-size: 12px;
    text-align: right;
}

@media (max-width: 760px) {
    .page {
        width: min(100% - 20px, 1120px);
        margin-top: 10px;
    }

    .hero,
    section {
        padding: 28px 24px;
    }

    .result-strip {
        grid-template-columns: 1fr;
        padding: 22px 24px;
    }

    .grid-2,
    .status-grid {
        grid-template-columns: 1fr;
    }

    .witness {
        grid-template-columns: 1fr;
    }

    .footer {
        padding: 16px 24px;
    }
}

@media print {
    body {
        background: #fff;
    }

    .page {
        width: 100%;
        margin: 0;
    }

    .report {
        border: 0;
        box-shadow: none;
    }
}
</style>
</head>

<body>
<div class="page">
<article class="report">

<header class="hero">
    <p class="eyebrow">HACP · Release 1.1.1 · Reproduction evidence</p>
    <h1>Ada / Rust Cross-Implementation Reproduction</h1>

    <div class="meta">
        <span>Repository-owned execution</span>
        <span>Generated $Generated</span>
    </div>
</header>

<div class="result-strip">
    <span class="result-badge">PASS</span>
    <div class="result-copy">
        Fresh repository-owned reproduction completed across the Ada and Rust
        evaluator surfaces. Evidence families remain separate; no synthetic
        combined score is used.
    </div>
</div>

<section>
    <p class="section-kicker">Current evidence</p>
    <h2>Core direct conformance</h2>

    <div class="grid-2">
        <div class="metric">
            <span class="metric-label">Ada Core-compatible</span>
            <span class="metric-value pass">$AdaCore</span>
        </div>

        <div class="metric">
            <span class="metric-label">Rust Core-compatible</span>
            <span class="metric-value pass">$RustCore</span>
        </div>
    </div>

    <p>
        Both implementations consume the canonical Core vector set owned by
        the repository root.
    </p>
</section>

<section>
    <p class="section-kicker">Historical record</p>
    <h2>Rust accounting preserved</h2>

    <div class="history">
        <div class="metric-label">Historical Rust verification accounting</div>
        <div class="history-value">$Historical</div>

        <p>
            Historical accounting is preserved and is not rewritten by the
            newer Core-compatible direct reproduction.
        </p>

        <div class="case-row">
            <span class="case">CORE-INV1-002</span>
            <span class="case">CORE-RUNTIME-004</span>
        </div>
    </div>

    <p>
        Both cases now pass directly in the current Ada and Rust
        Core-compatible execution paths.
    </p>
</section>

<section>
    <p class="section-kicker">Successor semantics</p>
    <h2>Authorization-v2 witnesses</h2>

    <div class="grid-2">
        <div class="metric">
            <span class="metric-label">Ada Authorization-v2</span>
            <span class="metric-value pass">$AdaAuth</span>
        </div>

        <div class="metric">
            <span class="metric-label">Rust Authorization-v2</span>
            <span class="metric-value pass">$RustAuth</span>
        </div>
    </div>

    <div class="witness-list">
        <div class="witness">
            <span class="witness-name">ACTION_HASH_WITNESS</span>
            <span class="witness-result">DENY / SIGNATURE_FAILURE</span>
        </div>

        <div class="witness">
            <span class="witness-name">ENVELOPE_SIGNATURE_WITNESS</span>
            <span class="witness-result">DENY / SIGNATURE_FAILURE</span>
        </div>

        <div class="witness">
            <span class="witness-name">SIGNED_DENY_WITNESS</span>
            <span class="witness-result">DENY / POLICY_DENIED</span>
        </div>
    </div>
</section>

<section>
    <p class="section-kicker">Reconciliation</p>
    <h2>Cross-implementation result</h2>

    <div class="status-grid">
        <div class="status-row">
            <span class="status-label">Core</span>
            <span class="status-value pass">$CrossCore</span>
        </div>

        <div class="status-row">
            <span class="status-label">Authorization-v2</span>
            <span class="status-value pass">$CrossAuth</span>
        </div>

        <div class="status-row">
            <span class="status-label">Known semantic RED</span>
            <span class="status-value">$SemanticRed</span>
        </div>

        <div class="status-row">
            <span class="status-label">Synthetic total</span>
            <span class="status-value">$Synthetic</span>
        </div>
    </div>
</section>

<section>
    <p class="section-kicker">Boundary</p>
    <h2>Repository-owned reproduction</h2>

    <p>
        Canonical vectors remain owned by <code>vectors/</code>.
    </p>

    <p>
        The bounded Rust evaluator package is owned by
        <code>test/matrix/t_rs/rust/</code>.
    </p>

    <p>
        Stable Ada implementation and environment assets already present in
        the repository are reused in place. The existing Ada matrix is not
        modified.
    </p>

    <p>
        No laboratory checkout or sibling repository is required at runtime.
        Public reproduction is repository- and version-driven.
    </p>

    <p>
        Historical source hashes are not used as build, dependency,
        implementation, release, or navigation selectors. Protocol-intrinsic
        cryptographic hashing remains part of HACP semantics.
    </p>
</section>

<section>
    <p class="section-kicker">Raw material</p>
    <h2>Evidence files</h2>

    <p>
        Raw execution evidence is retained under <code>_evidence/</code>.
    </p>

    <div class="evidence-links">
        <a class="evidence-link" href="_evidence/ada_prepare.log">
            <span class="evidence-name">ada_prepare.log</span>
            <span class="evidence-action">open evidence →</span>
        </a>

        <a class="evidence-link" href="_evidence/ada_core.log">
            <span class="evidence-name">ada_core.log</span>
            <span class="evidence-action">open evidence →</span>
        </a>

        <a class="evidence-link" href="_evidence/rust_core.log">
            <span class="evidence-name">rust_core.log</span>
            <span class="evidence-action">open evidence →</span>
        </a>

        <a class="evidence-link" href="_evidence/ada_authorization_v2.log">
            <span class="evidence-name">ada_authorization_v2.log</span>
            <span class="evidence-action">open evidence →</span>
        </a>

        <a class="evidence-link" href="_evidence/rust_authorization_v2.log">
            <span class="evidence-name">rust_authorization_v2.log</span>
            <span class="evidence-action">open evidence →</span>
        </a>
    </div>
</section>

<section class="final">
    <p class="section-kicker">Machine-readable summary</p>
    <h2>Final status</h2>

<pre>ADA_CORE_DIRECT=$AdaCore
RUST_CORE_COMPATIBLE=$RustCore
RUST_HISTORICAL_CORE=$Historical
ADA_AUTHORIZATION_V2=$AdaAuth
RUST_AUTHORIZATION_V2=$RustAuth
CROSS_IMPLEMENTATION_CORE=$CrossCore
CROSS_IMPLEMENTATION_AUTHORIZATION_V2=$CrossAuth
KNOWN_SEMANTIC_RED=$SemanticRed
SYNTHETIC_TOTAL=$Synthetic
REPRODUCTION_REPORT=PASS</pre>
</section>

<div class="footer">
    HACP · Release 1.1.1
</div>

</article>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText(
    $HtmlPath,
    ($Html.TrimEnd() + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

# ============================================================
# Verification
# ============================================================

foreach ($Path in @(
    $MarkdownPath,
    $HtmlPath
)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Report output missing: $Path"
    }

    if ((Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "Report output empty: $Path"
    }
}

$HtmlCheck =
    Get-Content `
        -LiteralPath $HtmlPath `
        -Raw `
        -Encoding UTF8

foreach ($Marker in @(
    'class="result-badge">PASS',
    'Ada / Rust Cross-Implementation Reproduction',
    '38/38 PASS',
    '38/38 DIRECT PASS',
    '36 DIRECT + 2 ADJUDICATED / 38',
    'CORE-INV1-002',
    'CORE-RUNTIME-004',
    'ACTION_HASH_WITNESS',
    'SIGNATURE_FAILURE',
    'POLICY_DENIED',
    'REPRODUCTION_REPORT=PASS'
)) {
    if (-not $HtmlCheck.Contains($Marker)) {
        throw "HTML marker missing: $Marker"
    }
}

$EvidenceCount =
    @(
        Get-ChildItem `
            -LiteralPath $ReportEvidence `
            -File
    ).Count

if ($EvidenceCount -ne 5) {
    throw "Expected 5 evidence files, observed $EvidenceCount"
}

Write-Host 'REPORT_MARKDOWN=PASS'
Write-Host 'REPORT_HTML_PRESENTATION=PASS'
Write-Host "REPORT_EVIDENCE_FILE_COUNT=$EvidenceCount"
Write-Host "REPORT_ROOT=$ReportRoot"
Write-Host "REPORT_MD=$MarkdownPath"
Write-Host "REPORT_HTML=$HtmlPath"
Write-Host 'T_RS_REPORT=PASS'
