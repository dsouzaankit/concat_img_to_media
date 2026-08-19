# Shuffles images and builds a randomized FHD slideshow video.
# Each image becomes a clip of $ImageIntervalSeconds (default 3s), then clips are concatenated.

param(
    [double]$ImageIntervalSeconds = 3,
    [int]$LimitMinutes = 60,
    [int]$MaxRandFileCount = 5000
)

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

$ImageExtStr = "*.jpg","*.jpeg","*.png","*.webp","*.bmp","*.tif","*.tiff"

# Anchor to script folder so relative paths work under double-click / odd cwd
$scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
Set-Location -LiteralPath $scriptRoot

$InputDir = Join-Path $scriptRoot "..\*"
$OutputDirName = "standardized"
$OutputDir = Join-Path $scriptRoot $OutputDirName
$FFmpegPath = "ffmpeg.exe"
$FilterScript = Join-Path $scriptRoot "filter_complex_fhd.txt"
$TempDir = Join-Path $env:TEMP "concat_img_slideshow"
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
# Fresh temp dir each run (also clears leftovers from interrupted runs)
Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

function Clear-SlideshowTemp {
    Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($ImageIntervalSeconds -le 0) {
    Write-Error "ImageIntervalSeconds must be > 0 (got $ImageIntervalSeconds)"
    exit 1
}

$intervalTag = ("{0}" -f $ImageIntervalSeconds) -replace '\.', 'p'
$clipSuffix = "_${intervalTag}s"

function Get-ClipFileName([string]$BaseName, [string]$Suffix) {
    # Keep trailing '_' identity from source name:
    #   a_b_c_id      -> b_c_id? No: last two -> c_id
    #   hash_id       -> hash_id
    #   3840x4800_hash -> hash only (drop WxH prefix; cloud sync chokes on long dim_hash paths)
    $parts = @($BaseName -split '_')
    if ($parts.Count -ge 3) {
        $tail = $parts[-2] + '_' + $parts[-1]
    } elseif ($parts.Count -eq 2 -and $parts[0] -match '^\d+x\d+$') {
        $tail = $parts[1]
    } elseif ($parts.Count -eq 2) {
        $tail = $parts[0] + '_' + $parts[1]
    } else {
        $tail = $BaseName
    }
    $tail = $tail -replace '[<>:"/\\|?*]', ''
    if ([string]::IsNullOrWhiteSpace($tail)) { $tail = 'clip' }
    return "${tail}${Suffix}.mp4"
}

function Test-UsableFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.Length -le 0) { return $false }
        # Touch-open: cloud sync can list ghost files that cannot be read
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $fs.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Publish-TempToDest {
    param(
        [string]$TempPath,
        [string]$DestPath
    )
    if (-not (Test-UsableFile $TempPath)) { return $false }

    $destDir = Split-Path -Parent $DestPath
    $destName = Split-Path -Leaf $DestPath
    New-Item -Path $destDir -ItemType Directory -Force | Out-Null

    # Stage as a short *_Ns.mp4 name first — cloud sync often fails creating/replacing certain final names
    $staging = Join-Path $destDir ('_up_' + [guid]::NewGuid().ToString('N').Substring(0, 12) + $clipSuffix + '.mp4')
    try {
        [System.IO.File]::Copy($TempPath, $staging, $true)
    } catch {
        Write-Host "Copy to staging failed: $($_.Exception.Message)"
        Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
        return $false
    } finally {
        Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-UsableFile $staging)) { return $false }

    Remove-Item -LiteralPath $DestPath -Force -ErrorAction SilentlyContinue
    try {
        Rename-Item -LiteralPath $staging -NewName $destName -ErrorAction Stop
    } catch {
        # Final name blocked (ghost placeholder): keep staged short *_Ns.mp4 (still picked up in Pass 2)
        Write-Host "Rename to '$destName' failed ($($_.Exception.Message)); keeping $(Split-Path -Leaf $staging)"
        return (Test-UsableFile $staging)
    }
    return (Test-UsableFile $DestPath)
}

function Invoke-FfmpegClip {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [string[]]$VideoCodecArgs
    )
    # Encode to local TEMP first (cloud sync often fails mid-write / ghost placeholders), then copy
    $tempOut = Join-Path $TempDir ("clip_" + [guid]::NewGuid().ToString('N') + ".mp4")

    # Build one argv string for ProcessStartInfo — avoids PowerShell globbing of [vout]/[aout]
    function Format-Arg([string]$s) {
        # Quote args with spaces or [] so CreateProcess keeps them intact
        if ($s -notmatch '[\s"\[\]]') { return $s }
        return '"' + ($s -replace '"', '\"') + '"'
    }
    $parts = @(
        '-y', '-loop', '1', '-t', "$ImageIntervalSeconds",
        '-i', $InputFile,
        '-f', 'lavfi', '-i', 'anullsrc',
        '-/filter_complex', $FilterScript,
        '-map', '[vout]', '-map', '[aout]'
    ) + $VideoCodecArgs + @(
        '-color_range', 'tv',
        '-colorspace', 'bt709',
        '-color_primaries', 'bt709',
        '-color_trc', 'bt709',
        '-c:a', 'aac',
        '-shortest',
        $tempOut
    )
    $argString = ($parts | ForEach-Object { Format-Arg $_ }) -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FFmpegPath
    $psi.Arguments = $argString
    $psi.WorkingDirectory = $scriptRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    # Inherit this console so ffmpeg progress/logs stay visible
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0 -or -not (Test-UsableFile $tempOut)) {
        Write-Host "ffmpeg exit=$($proc.ExitCode) temp usable=$(Test-UsableFile $tempOut)"
        Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        return $false
    }

    return (Publish-TempToDest -TempPath $tempOut -DestPath $OutputFile)
}

Write-Host "Image interval: $ImageIntervalSeconds s per image"
Write-Host "Standardizing images to $ImageIntervalSeconds-second FHD clips..."
Write-Host "Output dir: $OutputDir"

Get-ChildItem -Path $InputDir -Include $ImageExtStr -File | ForEach-Object {
    $BaseNameNoQuote = $_.BaseName.Replace("'", "")
    $OutputFile = Join-Path $OutputDir (Get-ClipFileName -BaseName $BaseNameNoQuote -Suffix $clipSuffix)

    if (Test-UsableFile $OutputFile) {
        Write-Host "File '$($_.Name)' already standardized. Skipping..."
        return
    }

    # Clear broken cloud-sync placeholders that block create
    Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue

    Write-Host "Processing: $($_.FullName)"
    Write-Host "Output to: $OutputFile"

    $qsvArgs = @('-c:v', 'hevc_qsv', '-global_quality', '20')
    $ok = Invoke-FfmpegClip -InputFile $_.FullName -OutputFile $OutputFile -VideoCodecArgs $qsvArgs
    if (-not $ok) {
        Write-Host "QSV encode failed for $($_.Name). Retrying with libx264..."
        $x264Args = @('-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p')
        $ok = Invoke-FfmpegClip -InputFile $_.FullName -OutputFile $OutputFile -VideoCodecArgs $x264Args
        if (-not $ok) {
            Write-Host "Skipping failed clip: $($_.Name)"
        }
    }
}

Write-Host "Batch image standardization complete"
Write-Host "Randomizing + concatenating clips up to >$LimitMinutes mins or $MaxRandFileCount files, whichever hits earlier!"

$allClips = @(
    Get-ChildItem -Path $OutputDir -Filter "*$clipSuffix.mp4" -File -ErrorAction SilentlyContinue |
    Where-Object { Test-UsableFile $_.FullName }
)
if ($allClips.Count -eq 0) {
    Write-Error "No standardized clips found in '$OutputDir' for interval ${ImageIntervalSeconds}s. Nothing to concatenate."
    exit 1
}

$pickCount = [Math]::Min($MaxRandFileCount, $allClips.Count)
$files = @($allClips | Get-Random -Count $pickCount)

$selectedFiles = @()
$totalSeconds = 0
$limitSeconds = $LimitMinutes * 60
foreach ($file in $files) {
    if ($totalSeconds -ge $limitSeconds) { break }
    $selectedFiles += $file.FullName
    $totalSeconds += $ImageIntervalSeconds
}

Write-Host "Selected $($selectedFiles.Count) clips; total duration: $([Math]::Round($totalSeconds / 60, 2)) minutes"

$PlaySeqFile = Join-Path $scriptRoot "img_file_seq.txt"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$lines = New-Object System.Collections.Generic.List[string]
foreach ($i in $selectedFiles) {
    $p = ($i -replace '\\', '/') -replace "'", "'\\''"
    $lines.Add("file '$p'")
}
[System.IO.File]::WriteAllLines($PlaySeqFile, $lines, $utf8NoBom)

$grandparentPath = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
$grandparentName = Split-Path -Path $grandparentPath -Leaf
$OutFile = Join-Path $grandparentPath "$grandparentName`_all_pics_${intervalTag}s.mp4"

# Concat to TEMP then copy to grandparent (cloud-sync-safe)
$tempFinal = Join-Path $TempDir ("final_" + [guid]::NewGuid().ToString('N') + ".mp4")
& $FFmpegPath -y -f concat -safe 0 -i $PlaySeqFile -c copy $tempFinal
if (-not (Test-UsableFile $tempFinal)) {
    Clear-SlideshowTemp
    Write-Error "Concat failed"
    exit 1
}
Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
if (-not (Publish-TempToDest -TempPath $tempFinal -DestPath $OutFile)) {
    Clear-SlideshowTemp
    Write-Error "Failed to publish final slideshow to $OutFile"
    exit 1
}

Clear-SlideshowTemp
Write-Host "Done: $OutFile"
