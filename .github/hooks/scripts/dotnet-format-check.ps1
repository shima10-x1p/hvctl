#requires -Version 7
<#
.SYNOPSIS
    PostToolUse hook: .cs ファイルが編集されたときだけ dotnet format の whitespace チェックを実行する。

.DESCRIPTION
    - stdin に JSON で渡される hook input (tool_name / tool_input.filePath) を解析する。
    - 編集系ツール (create_file / replace_string_in_file / multi_replace_string_in_file / edit など) で
      .cs ファイルを編集した場合だけ、対象ファイルに絞って dotnet format whitespace --verify-no-changes を走らせる。
    - 違反があれば exit 1 (non-blocking warning) として systemMessage を stdout に返す。
    - 該当しない場合・dotnet が無い場合・file path が取れない場合は exit 0 で静かに終了する。
    - エージェントの流れを止めないことを最優先する (exit 2 = blocking は使わない)。
#>

$ErrorActionPreference = 'Stop'

# 静かに成功終了するヘルパー
function Exit-Quiet {
    exit 0
}

# 警告メッセージを systemMessage として返してから exit 1 する
function Exit-Warn([string]$message) {
    $payload = @{
        systemMessage = $message
        continue      = $true
    } | ConvertTo-Json -Compress
    Write-Output $payload
    exit 1
}

# stdin が空 / hook 仕様外なら何もしない
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { Exit-Quiet }

try {
    $input = $raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Exit-Quiet
}

# 編集系ツールでなければスキップ
$toolName = [string]$input.tool_name
if ([string]::IsNullOrWhiteSpace($toolName)) { Exit-Quiet }

$editTools = @(
    'create_file',
    'replace_string_in_file',
    'multi_replace_string_in_file',
    'edit',
    'write',
    'Edit',
    'Write',
    'MultiEdit'
)
if ($editTools -notcontains $toolName) { Exit-Quiet }

# tool_input から file path を取り出す (キー名の揺れに耐える)
$toolInput = $input.tool_input
if ($null -eq $toolInput) { Exit-Quiet }

$candidatePaths = @()
foreach ($key in @('filePath', 'file_path', 'path')) {
    if ($null -ne $toolInput.$key) {
        $candidatePaths += [string]$toolInput.$key
    }
}

# multi_replace_string_in_file の場合: replacements 配列から filePath を集める
if ($null -ne $toolInput.replacements) {
    foreach ($r in $toolInput.replacements) {
        foreach ($key in @('filePath', 'file_path', 'path')) {
            if ($null -ne $r.$key) {
                $candidatePaths += [string]$r.$key
            }
        }
    }
}

$csFiles = $candidatePaths |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Where-Object { [System.IO.Path]::GetExtension($_).Equals('.cs', [System.StringComparison]::OrdinalIgnoreCase) } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -Unique

if ($csFiles.Count -eq 0) { Exit-Quiet }

# dotnet CLI が無ければ静かに終了 (警告も出さない)
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Exit-Quiet }

# .slnx / .sln を探す (リポジトリルートから上方向には行かない)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$solution = Get-ChildItem -LiteralPath $repoRoot -Filter '*.slnx' -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $solution) {
    $solution = Get-ChildItem -LiteralPath $repoRoot -Filter '*.sln' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if ($null -eq $solution) { Exit-Quiet }

# 各ファイルを solution に対する相対パスに正規化して dotnet format に渡す
$includeArgs = foreach ($f in $csFiles) {
    $abs = (Resolve-Path -LiteralPath $f).Path
    [System.IO.Path]::GetRelativePath($repoRoot, $abs)
}

# whitespace 検査のみ (高速)。違反があると exit code 非 0。
$args = @(
    'format', 'whitespace', $solution.FullName,
    '--verify-no-changes',
    '--include'
) + $includeArgs

$proc = & dotnet @args 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) { Exit-Quiet }

# フォーマット違反 (or dotnet format 自体の失敗) を non-blocking で通知
$summary = ($proc | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($summary)) {
    $summary = "(no output)"
}

$fileList = ($csFiles -join ', ')
Exit-Warn @"
dotnet format whitespace 違反を検出: $fileList
次のいずれかで修正してください:
  dotnet format whitespace $($solution.Name) --include $($includeArgs -join ' ')
--- detail ---
$summary
"@
