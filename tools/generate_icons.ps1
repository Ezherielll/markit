# MarkIt [M] icon generator.
#
# Merender logo "M dalam tile rounded pen-blue dengan dua bracket" dari
# font Fraunces (aset aplikasi) menggunakan System.Drawing, lalu menulis
# semua format ikon platform:
#   - windows/runner/resources/app_icon.ico   (16..256, PNG-encoded entries)
#   - macos/.../AppIcon.appiconset/app_icon_*.png
#   - web/favicon.png, web/icons/Icon-*.png, Icon-maskable-*.png
#   - assets/branding/markit_icon.png         (icon jendela Linux, 512)
#
# Usage: pwsh tools/generate_icons.ps1  (idempotent; tulis-menimpa)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$fontPath = Join-Path $repoRoot "assets\fonts\Fraunces.ttf"
if (-not (Test-Path $fontPath)) { throw "Font tidak ditemukan: $fontPath" }

# ── Brand colors ──────────────────────────────────────────────
$tileColor  = [System.Drawing.Color]::FromArgb(255, 39, 76, 138)     # penBlue #274C8A
$edgeColor  = [System.Drawing.Color]::FromArgb(255, 31, 63, 115)     # #1F3F73
$glyphColor = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)   # white
$bracketColor = [System.Drawing.Color]::FromArgb(252, 246, 244, 239) # paper #F6F4EF a≈0.99

# ── Geometry (fraksi dari tile) ───────────────────────────────
$tile        = 1024.0
$cornerF     = 0.090     # radius sudut tile
$edgeW       = 0.004     # hairline tepi tile
$boxWF       = 0.420     # lebar kotak huruf M
$boxHF       = 0.580     # tinggi kotak huruf M
$barInsetF   = 0.088     # jarak bracket dari tepi tile
$barWidthF   = 0.055     # lebar bracket
$barHeightF  = 0.600     # tinggi bracket
$minBarsPx   = 56.0      # ukuran < ini: tanpa bracket (agar tetap bersih)

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$fontFamily = $pfc.Families[0]

# ── Draw helpers ──────────────────────────────────────────────
function New-Canvas([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return @{ bmp = $bmp; g = $g }
}

function Draw-Mark([System.Drawing.Graphics]$g, [int]$size, [bool]$withBars, [double]$scale = 1.0) {
    $S = [double]$size
    $tilePath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $r = New-Object System.Drawing.RectangleF ([single]0), ([single]0), ([single]$S), ([single]$S)
    $rad = $S * $cornerF
    $d = $rad * 2
    $tilePath.AddArc($r.Left, $r.Top, $d, $d, 180, 90)
    $tilePath.AddArc($r.Right - $d, $r.Top, $d, $d, 270, 90)
    $tilePath.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $tilePath.AddArc($r.Left, $r.Bottom - $d, $d, $d, 90, 90)
    $tilePath.CloseFigure()
    $brush = New-Object System.Drawing.SolidBrush($tileColor)
    $g.FillPath($brush, $tilePath)

    # hairline tepi
    $pen = New-Object System.Drawing.Pen($edgeColor, [Math]::Max(1.0, $S * $edgeW))
    $pen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Inset
    $g.DrawPath($pen, $tilePath)

    $cx = $S / 2.0
    $cy = $S / 2.0
    $boxW = $S * $boxWF * $scale
    $boxH = $S * $boxHF * $scale

    # M serif Fraunces — diukur lalu diskalakan agar pas dalam kotak
    $fmt = [System.Drawing.StringFormat]::GenericTypographic
    $trial = $S * 0.72 * $scale
    $measureBmp = New-Object System.Drawing.Bitmap([int]$S, [int]$S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $mg = [System.Drawing.Graphics]::FromImage($measureBmp)
    $measureFont = New-Object System.Drawing.Font($fontFamily, [single]$trial, [System.Drawing.FontStyle]::Regular)
    $mSize = $mg.MeasureString("M", $measureFont, 0, $fmt)
    $mg.Dispose(); $measureBmp.Dispose()
    $f = [Math]::Min($boxW / [Math]::Max($mSize.Width, 1.0), $boxH / [Math]::Max($mSize.Height, 1.0))
    $glyphFont = New-Object System.Drawing.Font($fontFamily, [single]($trial * $f), [System.Drawing.FontStyle]::Regular)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $glyphSize = $g.MeasureString("M", $glyphFont, 0, $fmt)
    $g.DrawString("M", $glyphFont, (New-Object System.Drawing.SolidBrush($glyphColor)),
                  [single]($cx - $glyphSize.Width / 2), [single]($cy - $glyphSize.Height / 2), $fmt)

    if ($withBars -and $S -ge $minBarsPx) {
        $bw = $S * $barWidthF
        $bh = $S * $barHeightF * $scale
        $by = $cy - $bh / 2.0
        $barBrush = New-Object System.Drawing.SolidBrush($bracketColor)
        $gap = $S * $barInsetF
        foreach ($bx in @($gap, ($S - $gap - $bw))) {
            $bp = New-Object System.Drawing.Drawing2D.GraphicsPath
            # pill vertikal: cap atas & bawah, diameter = bw (bw < bh selalu)
            $bp.AddArc([single]$bx, [single]$by, [single]$bw, [single]$bw, 180, 180)
            $bp.AddArc([single]$bx, [single]($by + $bh - $bw), [single]$bw, [single]$bw, 0, 180)
            $bp.CloseFigure()
            $g.FillPath($barBrush, $bp)
            $bp.Dispose()
        }
    }

    $brush.Dispose()
    if ($pen) { $pen.Dispose() }
}

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$path) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "  wrote $($bmp.Width)x$($bmp.Height)  $($path.Replace($repoRoot,'.'))"
}

function New-Scaled([System.Drawing.Bitmap]$src, [int]$size) {
    $c = New-Canvas $size
    $c.g.DrawImage($src, 0, 0, $size, $size)
    return $c.bmp
}

function New-Transparent([int]$size) {
    return (New-Canvas $size).bmp
}

# ── Render master 1024 (dengan & tanpa bracket) ───────────────
$cFull = New-Canvas 1024; Draw-Mark $cFull.g 1024 $true; $masterFull = $cFull.bmp
$cPlain = New-Canvas 1024; Draw-Mark $cPlain.g 1024 $false; $masterPlain = $cPlain.bmp

# ── Windows ICO (16/24/32/48/64/128/256) ──────────────────────
function New-Ico([System.Drawing.Bitmap]$src, [int[]]$sizes, [string]$path) {
    $entries = @()   # list of hashtable: data + dim
    foreach ($sz in $sizes) {
        $img = New-Scaled $src $sz
        $ms = New-Object System.IO.MemoryStream
        $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $entries += ,@{ data = $ms.ToArray(); dim = $sz }
        $img.Dispose()
    }
    $fs = [System.IO.File]::Create($path)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)
    $offset = 6 + 16 * $entries.Count
    foreach ($e in $entries) {
        $dim = $e.dim
        if ($dim -ge 256) { $dim = 0 }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim)
        $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$e.data.Length); $bw.Write([uint32]$offset)
        $offset += $e.data.Length
    }
    foreach ($e in $entries) { $bw.Write($e.data) }
    $bw.Close(); $fs.Close()
    Write-Host "  wrote ICO ($($sizes -join '/'))  $($path.Replace($repoRoot,'.'))"
}

$icoSizes = @(16, 24, 32, 48, 64, 128, 256)
$winIco = Join-Path $repoRoot "windows\runner\resources\app_icon.ico"
New-Ico $masterFull $icoSizes $winIco

# ── macOS appiconset ──────────────────────────────────────────
$macDir = Join-Path $repoRoot "macos\Runner\Assets.xcassets\AppIcon.appiconset"
foreach ($sz in @(16, 32, 64, 128, 256, 512, 1024)) {
    $src = if ($sz -lt $minBarsPx) { $masterPlain } else { $masterFull }
    $bmp = New-Scaled $src $sz
    Save-Png $bmp (Join-Path $macDir "app_icon_$sz.png")
    $bmp.Dispose()
}

# ── Web ───────────────────────────────────────────────────────
$webIcons = Join-Path $repoRoot "web\icons"
foreach ($sz in @(192, 512)) {
    $bmp = New-Scaled $masterFull $sz
    Save-Png $bmp (Join-Path $webIcons "Icon-$sz.png")
    $bmp.Dispose()
}
foreach ($sz in @(192, 512)) {
    # maskable: M+bracket dalam safe-zone 66%, tile tetap full-bleed
    $c = New-Canvas $sz
    Draw-Mark $c.g $sz $true 0.66
    $bmp = $c.bmp
    Save-Png $bmp (Join-Path $webIcons "Icon-maskable-$sz.png")
    $bmp.Dispose()
}
$fav = New-Scaled $masterPlain 32
Save-Png $fav (Join-Path $repoRoot "web\favicon.png")
$fav.Dispose()

# ── Linux window icon ─────────────────────────────────────────
$brandingDir = Join-Path $repoRoot "assets\branding"
if (-not (Test-Path $brandingDir)) { New-Item -ItemType Directory -Path $brandingDir -Force | Out-Null }
$linuxIcon = New-Scaled $masterFull 512
Save-Png $linuxIcon (Join-Path $brandingDir "markit_icon.png")
$linuxIcon.Dispose()

$masterFull.Dispose(); $masterPlain.Dispose()
$cFull.g.Dispose(); $cPlain.g.Dispose()
$pfc.Dispose()

Write-Host ""
Write-Host "Done: semua ikon [M] MarkIt dihasilkan."


