[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectFile,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [ValidateSet('preview', 'a1-150ppi', 'a1-300ppi')][string]$Preset = 'a1-150ppi'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not (Test-Path -LiteralPath $ProjectFile)) { throw "未找到项目资料包：$ProjectFile" }
if (-not (Test-Path -LiteralPath $OutputDir)) { throw "未找到导出目录：$OutputDir" }

$project = Get-Content -Raw -LiteralPath $ProjectFile | ConvertFrom-Json
$sizes = @{
    preview      = @{ Width = 1754; Height = 2483; Ppi = 150 }
    'a1-150ppi'  = @{ Width = 3508; Height = 4967; Ppi = 150 }
    'a1-300ppi'  = @{ Width = 7016; Height = 9933; Ppi = 300 }
}
$target = $sizes[$Preset]
$boards = @(
    @{ Code = 'BOARD 01'; File = "$($project.projectId)-board-01-context.png" },
    @{ Code = 'BOARD 02'; File = "$($project.projectId)-board-02-architecture.png" },
    @{ Code = 'BOARD 03'; File = "$($project.projectId)-board-03-application.png" }
)
$results = @()
$failed = $false

foreach ($board in $boards) {
    $file = Join-Path $OutputDir $board.File
    $item = [ordered]@{
        board = $board.Code; file = $board.File; exists = Test-Path -LiteralPath $file
        widthPx = $null; heightPx = $null; horizontalDpi = $null; verticalDpi = $null
        bytes = $null; status = 'PASS'; notes = @()
    }
    if (-not $item.exists) {
        $item.status = 'FAIL'; $item.notes += '缺少预期 PNG 文件。'; $failed = $true
    } else {
        $info = Get-Item -LiteralPath $file
        $item.bytes = $info.Length
        try {
            $img = [System.Drawing.Image]::FromFile($file)
            try {
                $item.widthPx = $img.Width; $item.heightPx = $img.Height
                $item.horizontalDpi = [Math]::Round($img.HorizontalResolution, 2)
                $item.verticalDpi = [Math]::Round($img.VerticalResolution, 2)
            } finally { $img.Dispose() }
        } catch {
            $item.status = 'FAIL'; $item.notes += "PNG 无法读取：$($_.Exception.Message)"; $failed = $true
        }
        if ($item.widthPx -ne $target.Width -or $item.heightPx -ne $target.Height) {
            $item.status = 'FAIL'
            $item.notes += "像素尺寸为 $($item.widthPx)×$($item.heightPx)，应为 $($target.Width)×$($target.Height)。"
            $failed = $true
        }
        if ($item.bytes -le 0) { $item.status = 'FAIL'; $item.notes += '文件大小为 0。'; $failed = $true }
        if ($item.horizontalDpi -ne $target.Ppi -or $item.verticalDpi -ne $target.Ppi) {
            $item.status = 'WARN'
            $item.notes += "PNG 嵌入分辨率为 $($item.horizontalDpi)×$($item.verticalDpi) dpi；目标为 $($target.Ppi) dpi。像素尺寸已单独校验。"
        }
    }
    $results += [pscustomobject]$item
}

$report = [ordered]@{
    generatedAt = (Get-Date).ToString('o'); projectId = $project.projectId; preset = $Preset
    expected = @{ widthPx = $target.Width; heightPx = $target.Height; ppi = $target.Ppi }
    overallStatus = if ($failed) { 'FAIL' } elseif ($results.status -contains 'WARN') { 'WARN' } else { 'PASS' }
    boards = $results
    caveats = @(
        '此检查只验证文件存在性、PNG 可读性、像素尺寸和嵌入 PPI 元数据，不替代人工视觉审核。',
        '导出为 RGB PNG；印刷 PDF、CMYK、ICC、出血与裁切规范需依据印厂要求另行制作。'
    )
}
$reportFile = Join-Path $OutputDir 'QA-REPORT.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportFile -Encoding utf8
$results | Select-Object board, status, widthPx, heightPx, horizontalDpi, verticalDpi, bytes, notes | Format-Table -AutoSize
Write-Host "QA $($report.overallStatus)  报告：$reportFile" -ForegroundColor $(if ($failed) { 'Red' } elseif ($report.overallStatus -eq 'WARN') { 'Yellow' } else { 'Green' })
if ($failed) { exit 1 }
