[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectFile,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [ValidateSet('preview', 'a1-150ppi', 'a1-300ppi')][string]$Preset = 'a1-150ppi'
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'validate-project.ps1') -ProjectFile $ProjectFile -Preset $Preset
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Add-Type -AssemblyName System.Drawing
$sizes = @{
    preview      = @{ Width = 1754; Height = 2483; Ppi = 150 }
    'a1-150ppi'  = @{ Width = 3508; Height = 4967; Ppi = 150 }
    'a1-300ppi'  = @{ Width = 7016; Height = 9933; Ppi = 300 }
}
$size = $sizes[$Preset]
$canvasWidth = [int]$size.Width
$canvasHeight = [int]$size.Height
$u = $canvasWidth / 1000.0
$projectPath = Resolve-Path -LiteralPath $ProjectFile
$projectRoot = Split-Path -Parent $projectPath
$project = Get-Content -Raw -LiteralPath $projectPath | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function C([string]$hex) { return [System.Drawing.ColorTranslator]::FromHtml($hex) }
function X([double]$value) { return [int][Math]::Round($value * $u) }
function Rect([double]$x, [double]$y, [double]$w, [double]$h) { return [System.Drawing.Rectangle]::new((X $x), (X $y), (X $w), (X $h)) }
function Pt([double]$x, [double]$y) { return [System.Drawing.Point]::new((X $x), (X $y)) }
function F([string]$family, [double]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    return [System.Drawing.Font]::new($family, [single](X $size), $style, [System.Drawing.GraphicsUnit]::Pixel)
}
function Resolve-Asset([string]$relativePath) {
    return [System.IO.Path]::GetFullPath((Join-Path $projectRoot $relativePath))
}
function Draw-Rect($g, $rect, $fill, $stroke, [double]$strokeWidth = 1) {
    if ($null -ne $fill) { $brush = [System.Drawing.SolidBrush]::new($fill); $g.FillRectangle($brush, $rect); $brush.Dispose() }
    if ($null -ne $stroke) { $pen = [System.Drawing.Pen]::new($stroke, [single](X $strokeWidth)); $g.DrawRectangle($pen, $rect); $pen.Dispose() }
}
function Draw-Line($g, [double]$x1, [double]$y1, [double]$x2, [double]$y2, $color, [double]$width = 1) {
    $pen = [System.Drawing.Pen]::new($color, [single](X $width))
    $g.DrawLine($pen, $(Pt $x1 $y1), $(Pt $x2 $y2))
    $pen.Dispose()
}
function Draw-Text($g, [string]$text, [string]$fontName, [double]$fontSize, $color, $rect, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular, [System.Drawing.StringAlignment]$align = [System.Drawing.StringAlignment]::Near) {
    $font = F $fontName $fontSize $style
    $brush = [System.Drawing.SolidBrush]::new($color)
    $format = [System.Drawing.StringFormat]::new()
    $format.Alignment = $align
    $format.LineAlignment = [System.Drawing.StringAlignment]::Near
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisWord
    $rectF = [System.Drawing.RectangleF]::new([single]$rect.X, [single]$rect.Y, [single]$rect.Width, [single]$rect.Height)
    $g.DrawString($text, $font, $brush, $rectF, $format)
    $format.Dispose(); $brush.Dispose(); $font.Dispose()
}
function Draw-Cover($g, [string]$file, $dest, [string]$verticalAlign = 'center') {
    $image = [System.Drawing.Image]::FromFile($file)
    try {
        $srcAspect = $image.Width / [double]$image.Height
        $destAspect = $dest.Width / [double]$dest.Height
        if ($srcAspect -gt $destAspect) {
            $sourceHeight = $image.Height
            $sourceWidth = [int]($sourceHeight * $destAspect)
            $sourceX = [int](($image.Width - $sourceWidth) / 2)
            $source = [System.Drawing.Rectangle]::new($sourceX, 0, $sourceWidth, $sourceHeight)
        } else {
            $sourceWidth = $image.Width
            $sourceHeight = [int]($sourceWidth / $destAspect)
            $sourceY = if ($verticalAlign -eq 'top') { 0 } elseif ($verticalAlign -eq 'bottom') { $image.Height - $sourceHeight } else { [int](($image.Height - $sourceHeight) / 2) }
            $source = [System.Drawing.Rectangle]::new(0, $sourceY, $sourceWidth, $sourceHeight)
        }
        $g.DrawImage($image, $dest, $source, [System.Drawing.GraphicsUnit]::Pixel)
    } finally { $image.Dispose() }
}
function Draw-Contain($g, [string]$file, $dest) {
    $image = [System.Drawing.Image]::FromFile($file)
    try {
        $ratio = [Math]::Min($dest.Width / [double]$image.Width, $dest.Height / [double]$image.Height)
        $w = [int]($image.Width * $ratio); $h = [int]($image.Height * $ratio)
        $r = [System.Drawing.Rectangle]::new($dest.X + [int](($dest.Width - $w) / 2), $dest.Y + [int](($dest.Height - $h) / 2), $w, $h)
        $g.DrawImage($image, $r)
    } finally { $image.Dispose() }
}
function New-Board {
    $bmp = [System.Drawing.Bitmap]::new($canvasWidth, $canvasHeight, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $bmp.SetResolution([single]$size.Ppi, [single]$size.Ppi)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear((C $project.theme.background))
    return @{ Image = $bmp; Graphics = $g }
}
function Add-Chrome($g, [string]$boardCode, [string]$sectionCn, [string]$sectionEn) {
    $primary = C $project.theme.primary; $ink = C $project.theme.ink; $muted = C $project.theme.muted
    Draw-Line $g 34 31 966 31 $primary 1
    Draw-Line $g 34 31 34 48 $primary 1
    Draw-Line $g 966 31 966 48 $primary 1
    Draw-Text $g $boardCode 'Bahnschrift SemiBold' 9 $primary $(Rect 42 46 90 16)
    Draw-Text $g $sectionCn 'Microsoft YaHei UI' 12 $ink $(Rect 140 46 250 20) ([System.Drawing.FontStyle]::Bold)
    Draw-Text $g $sectionEn 'Bahnschrift' 8 $muted $(Rect 140 65 350 16)
    Draw-Line $g 34 1378 966 1378 $primary 1
    Draw-Text $g "INDUSTRIAL DESIGN SYSTEM  /  $($project.projectId.ToUpper())" 'Bahnschrift' 7 $muted $(Rect 34 1390 530 14)
    Draw-Text $g 'CONCEPT ONLY · NO CLINICAL CLAIMS' 'Bahnschrift' 7 $muted $(Rect 620 1390 346 14) ([System.Drawing.FontStyle]::Regular) ([System.Drawing.StringAlignment]::Far)
}
function Add-Title($g) {
    $ink = C $project.theme.ink; $primary = C $project.theme.primary; $accent = C $project.theme.accent
    Draw-Text $g $project.title 'Bahnschrift SemiBold' 38 $accent $(Rect 42 86 680 48)
    Draw-Text $g $project.subtitle 'Bahnschrift' 9 $ink $(Rect 44 127 600 16)
    Draw-Text $g $project.titleCn 'Microsoft YaHei UI' 19 $primary $(Rect 42 151 640 35) ([System.Drawing.FontStyle]::Bold)
}
function Add-Card($g, [double]$x, [double]$y, [double]$w, [double]$h, [string]$tag, [string]$title, [string]$body, [string]$icon = '') {
    $panel = C '#0A1217'; $primary = C $project.theme.primary; $ink = C $project.theme.ink; $muted = C $project.theme.muted
    Draw-Rect $g $(Rect $x $y $w $h) $panel $primary 0.7
    Draw-Line $g ($x + 12) ($y + 17) ($x + 47) ($y + 17) (C $project.theme.accent) 2
    Draw-Text $g $tag 'Bahnschrift SemiBold' 8 $primary $(Rect ($x + 12) ($y + 28) ($w - 24) 13)
    if ($icon) { Draw-Text $g $icon 'Arial Unicode MS' 19 $primary $(Rect ($x + $w - 46) ($y + 22) 28 28) ([System.Drawing.FontStyle]::Regular) ([System.Drawing.StringAlignment]::Center) }
    Draw-Text $g $title 'Microsoft YaHei UI' 13 $ink $(Rect ($x + 12) ($y + 50) ($w - 24) 25) ([System.Drawing.FontStyle]::Bold)
    Draw-Text $g $body 'Microsoft YaHei UI' 9 $muted $(Rect ($x + 12) ($y + 80) ($w - 24) ($h - 92))
}
function Save-Board($canvas, [string]$file) {
    $canvas.Graphics.Dispose()
    $canvas.Image.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Image.Dispose()
}

$master = Resolve-Asset $project.assets.master
$hero = Resolve-Asset $project.assets.hero
$structure = Resolve-Asset $project.assets.structure
$application = Resolve-Asset $project.assets.application
$ink = C $project.theme.ink; $primary = C $project.theme.primary; $muted = C $project.theme.muted; $accent = C $project.theme.accent

# Board 01 — context and hero
$b = New-Board; $g = $b.Graphics
Add-Chrome $g 'BOARD 01' $project.board1.kickerCn $project.board1.kickerEn
Add-Title $g
Draw-Cover $g $hero $(Rect 42 218 590 655)
Draw-Rect $g $(Rect 654 218 304 655) (C '#071015') $primary 0.8
Draw-Text $g '设计语境 / DESIGN INTENT' 'Microsoft YaHei UI' 13 $ink $(Rect 676 246 250 28) ([System.Drawing.FontStyle]::Bold)
Draw-Text $g $project.board1.lead 'Microsoft YaHei UI' 13 $muted $(Rect 676 292 250 115)
for ($i = 0; $i -lt $project.board1.insights.Count; $i++) {
    $y = 446 + 118 * $i
    Draw-Line $g 677 $y 698 $y $accent 2
    Draw-Text $g ("0" + ($i + 1)) 'Bahnschrift SemiBold' 9 $primary $(Rect 706 ($y - 10) 36 17)
    Draw-Text $g $project.board1.insights[$i] 'Microsoft YaHei UI' 10 $ink $(Rect 746 ($y - 14) 190 60)
}
for ($i = 0; $i -lt 3; $i++) {
    $card = $project.board1.cards[$i]
    Add-Card $g (42 + 306 * $i) 906 286 196 ("INSIGHT 0" + ($i + 1)) $card.title $card.body $card.icon
}
Draw-Rect $g $(Rect 42 1130 916 205) (C '#071015') $primary 0.8
Draw-Text $g '设计叙事 / NARRATIVE' 'Microsoft YaHei UI' 12 $ink $(Rect 62 1153 250 24) ([System.Drawing.FontStyle]::Bold)
Draw-Text $g '场景层建立临床空间的气氛；产品层锁定结构与 CMF；信息层通过一致的蓝色技术线、琥珀状态点与分区网格，把概念转译为可读的工业设计故事。' 'Microsoft YaHei UI' 13 $muted $(Rect 62 1194 820 52)
for ($i = 0; $i -lt 7; $i++) { Draw-Line $g (62 + 122 * $i) 1284 (150 + 122 * $i) 1284 $primary 1; Draw-Line $g (62 + 122 * $i) 1284 (62 + 122 * $i) 1302 $accent 2 }
Save-Board $b (Join-Path $OutputDir "$($project.projectId)-board-01-context.png")

# Board 02 — architecture and CMF
$b = New-Board; $g = $b.Graphics
Add-Chrome $g 'BOARD 02' $project.board2.kickerCn $project.board2.kickerEn
Add-Title $g
Draw-Rect $g $(Rect 42 218 564 836) (C '#071015') $primary 0.8
Draw-Contain $g $structure $(Rect 58 235 532 802)
Draw-Rect $g $(Rect 628 218 330 836) (C '#071015') $primary 0.8
Draw-Text $g '核心模块 / SYSTEM MODULES' 'Microsoft YaHei UI' 13 $ink $(Rect 650 246 278 25) ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt 3; $i++) {
    $module = $project.board2.modules[$i]; $y = 303 + $i * 192
    Draw-Line $g 650 $y 930 $y $primary 0.8
    Draw-Text $g $module.code 'Bahnschrift SemiBold' 16 $accent $(Rect 650 ($y + 16) 42 23)
    Draw-Text $g $module.title 'Microsoft YaHei UI' 13 $ink $(Rect 703 ($y + 14) 210 26) ([System.Drawing.FontStyle]::Bold)
    Draw-Text $g $module.body 'Microsoft YaHei UI' 10 $muted $(Rect 703 ($y + 52) 212 74)
    Draw-Line $g 704 ($y + 145) 902 ($y + 145) (C '#27404E') 1
}
Draw-Text $g 'CMF PALETTE' 'Bahnschrift SemiBold' 10 $primary $(Rect 650 912 220 16)
for ($i = 0; $i -lt $project.board2.cmf.Count; $i++) {
    $cmf = $project.board2.cmf[$i]; $y = 944 + 26 * $i
    Draw-Rect $g $(Rect 650 $y 22 16) (C $cmf.hex) $null
    Draw-Text $g $cmf.name 'Bahnschrift' 8 $ink $(Rect 682 ($y - 1) 180 14)
    Draw-Text $g $cmf.hex 'Bahnschrift' 7 $muted $(Rect 844 ($y) 78 14) ([System.Drawing.FontStyle]::Regular) ([System.Drawing.StringAlignment]::Far)
}
Draw-Rect $g $(Rect 42 1080 916 255) (C '#071015') $primary 0.8
Draw-Text $g '结构逻辑 / FORM LANGUAGE' 'Microsoft YaHei UI' 13 $ink $(Rect 62 1103 320 25) ([System.Drawing.FontStyle]::Bold)
Draw-Contain $g $master $(Rect 62 1140 268 170)
Draw-Text $g '母版用于锁定产品轮廓、构件数量和 CMF。结构资产只承担局部关系、细节和分解信息，不能改变已批准产品身份。' 'Microsoft YaHei UI' 12 $muted $(Rect 360 1164 538 70)
Draw-Line $g 360 1260 898 1260 $primary 1
Draw-Text $g 'MASTER → STRUCTURE → NATIVE CALLOUTS → EXPORT' 'Bahnschrift SemiBold' 9 $accent $(Rect 360 1281 520 16)
Save-Board $b (Join-Path $OutputDir "$($project.projectId)-board-02-architecture.png")

# Board 03 — application and workflow
$b = New-Board; $g = $b.Graphics
Add-Chrome $g 'BOARD 03' $project.board3.kickerCn $project.board3.kickerEn
Add-Title $g
Draw-Cover $g $application $(Rect 42 218 916 510) $project.board3.crop
Draw-Rect $g $(Rect 42 752 916 254) (C '#071015') $primary 0.8
Draw-Text $g '工作流程 / COLLABORATION FLOW' 'Microsoft YaHei UI' 13 $ink $(Rect 62 778 390 25) ([System.Drawing.FontStyle]::Bold)
$count = $project.board3.workflow.Count
for ($i = 0; $i -lt $count; $i++) {
    $step = $project.board3.workflow[$i]; $x = 62 + (876 / $count) * $i
    if ($i -lt ($count - 1)) { Draw-Line $g ($x + 60) 866 ($x + (876 / $count)) 866 $primary 2 }
    $brush = [System.Drawing.SolidBrush]::new((C '#0C1A22')); $g.FillEllipse($brush, $(Rect ($x + 12) 842 42 42)); $brush.Dispose()
    $pen = [System.Drawing.Pen]::new($primary, [single](X 1)); $g.DrawEllipse($pen, $(Rect ($x + 12) 842 42 42)); $pen.Dispose()
    Draw-Text $g $step.step 'Bahnschrift SemiBold' 9 $accent $(Rect ($x + 12) 855 42 14) ([System.Drawing.FontStyle]::Regular) ([System.Drawing.StringAlignment]::Center)
    Draw-Text $g $step.title 'Microsoft YaHei UI' 12 $ink $(Rect $x 904 (876 / $count) 21) ([System.Drawing.FontStyle]::Bold) ([System.Drawing.StringAlignment]::Center)
    Draw-Text $g $step.body 'Microsoft YaHei UI' 8 $muted $(Rect $x 932 (876 / $count) 34) ([System.Drawing.FontStyle]::Regular) ([System.Drawing.StringAlignment]::Center)
}
Draw-Rect $g $(Rect 42 1030 548 305) (C '#071015') $primary 0.8
Draw-Text $g '概念指标 / DESIGN-INTENT METRICS' 'Microsoft YaHei UI' 13 $ink $(Rect 62 1054 380 24) ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $project.board3.metrics.Count; $i++) {
    $metric = $project.board3.metrics[$i]; $y = 1110 + 60 * $i
    Draw-Text $g $metric.label 'Microsoft YaHei UI' 10 $ink $(Rect 62 $y 140 16)
    Draw-Rect $g $(Rect 212 ($y + 3) 300 13) (C '#16252D') $null
    Draw-Rect $g $(Rect 212 ($y + 3) (3 * [double]$metric.value) 13) $primary $null
    Draw-Text $g "$($metric.value)%" 'Bahnschrift SemiBold' 9 $accent $(Rect 522 ($y - 1) 45 16) ([System.Drawing.FontStyle]::Regular) ([System.Drawing.StringAlignment]::Far)
}
Draw-Text $g '指标仅用于版式层级演示，不是技术性能或临床结果。' 'Microsoft YaHei UI' 9 $muted $(Rect 62 1292 480 18)
Draw-Rect $g $(Rect 612 1030 346 305) (C '#071015') $primary 0.8
Draw-Text $g '使用边界 / NOTES' 'Microsoft YaHei UI' 13 $ink $(Rect 632 1054 270 24) ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $project.board3.notes.Count; $i++) {
    $y = 1110 + $i * 92
    Draw-Line $g 632 $y 654 $y $accent 2
    Draw-Text $g $project.board3.notes[$i] 'Microsoft YaHei UI' 10 $muted $(Rect 668 ($y - 8) 255 58)
}
Save-Board $b (Join-Path $OutputDir "$($project.projectId)-board-03-application.png")

Write-Host "已导出三张 $Preset 海报到：$(Resolve-Path -LiteralPath $OutputDir)" -ForegroundColor Green
