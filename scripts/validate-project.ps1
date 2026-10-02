[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectFile,
    [ValidateSet('preview', 'a1-150ppi', 'a1-300ppi')][string]$Preset = 'a1-150ppi'
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectAsset([string]$RelativePath) {
    $base = Split-Path -Parent (Resolve-Path -LiteralPath $ProjectFile)
    return [System.IO.Path]::GetFullPath((Join-Path $base $RelativePath))
}

if (-not (Test-Path -LiteralPath $ProjectFile)) { throw "未找到项目资料包：$ProjectFile" }
$project = Get-Content -Raw -LiteralPath $ProjectFile | ConvertFrom-Json
$required = 'projectId', 'title', 'subtitle', 'theme', 'assets', 'board1', 'board2', 'board3'
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
foreach ($field in $required) {
    if ($null -eq $project.$field -or [string]::IsNullOrWhiteSpace([string]$project.$field)) {
        $errors.Add("缺少必填字段：$field")
    }
}

foreach ($field in 'background', 'ink', 'primary', 'accent') {
    if ($project.theme.$field -notmatch '^#[0-9A-Fa-f]{6}$') { $errors.Add("theme.$field 必须是 #RRGGBB：当前为 '$($project.theme.$field)'") }
}

Add-Type -AssemblyName System.Drawing
$target = @{ preview = 1754; 'a1-150ppi' = 3508; 'a1-300ppi' = 7016 }[$Preset]
foreach ($assetName in 'master', 'hero', 'structure', 'application') {
    $asset = Resolve-ProjectAsset $project.assets.$assetName
    if (-not (Test-Path -LiteralPath $asset)) {
        $errors.Add("找不到 $assetName 图像：$asset")
        continue
    }
    $img = [System.Drawing.Image]::FromFile($asset)
    try {
        if ($img.Width -lt ($target * 0.55)) {
            $warnings.Add("$assetName 为 $($img.Width)×$($img.Height) px；在 $Preset 成品中会被明显放大，应补充高分辨率资产。")
        }
    } finally { $img.Dispose() }
}

if ($project.board1.cards.Count -lt 3) { $errors.Add('board1.cards 至少需要 3 张分析卡。') }
if ($project.board2.modules.Count -lt 3) { $errors.Add('board2.modules 至少需要 3 个结构模块。') }
if ($project.board3.workflow.Count -lt 3) { $errors.Add('board3.workflow 至少需要 3 个流程步骤。') }

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host "PASS  项目资料：$($project.projectId)" -ForegroundColor Green
$warnings | ForEach-Object { Write-Warning $_ }
Write-Host "提示：输出为 RGB PNG。若需要印刷 PDF/CMYK，请在获得印厂 ICC、出血和 PDF 规范后制作独立生产副本。" -ForegroundColor Yellow
