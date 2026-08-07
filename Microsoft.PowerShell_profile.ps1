<#
.SYNOPSIS
    PowerShell profile — shell configuration, Unix-style helpers, and utilities.

.DESCRIPTION
    Loaded automatically by PowerShell on startup. Sets the console to UTF-8,
    configures PSReadLine, imports modules, and defines a handful of convenience
    functions and aliases.

.NOTES
    Author : Jeremy Hart
    Path   : $PROFILE
#>

#region Console & Encoding

# Use UTF-8 for input and output so emoji, accents, and box-drawing render correctly.
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

#endregion

#region Modules & PSReadLine

Import-Module ExtractMP3 -WarningAction SilentlyContinue
Import-Module CompletionPredictor

Set-PSReadLineOption -ShowToolTips:$true
Set-PSReadLineOption -BellStyle None

#endregion

#region Coreutils

<#
    Microsoft Coreutils for Windows installs to "C:\Program Files\coreutils\bin".

    PowerShell resolves names in the order Alias > Function > Cmdlet > Application,
    so the built-in aliases (ls, cat, cp, ...) shadow the coreutils binaries even
    when the bin folder is on PATH. The aliases have to be removed for the
    binaries to win.

    Everything here is guarded by the bin folder existing. If coreutils isn't
    installed, the aliases are left alone and the shell behaves as normal.
#>

$CoreutilsBin = Join-Path $env:ProgramFiles 'coreutils\bin'

if (Test-Path $CoreutilsBin) {

    # Only remove an alias when a matching .exe is actually there, so nothing is
    # stripped without a replacement to fall through to.
    Get-Alias | ForEach-Object {
        if (Test-Path (Join-Path $CoreutilsBin "$($_.Name).exe")) {
            Remove-Item -Path "Alias:$($_.Name)" -Force -ErrorAction SilentlyContinue
        }
    }

    # winget doesn't add coreutils to PATH, so put it first for this session.
    $pathEntries = @($env:PATH -split ';' | Where-Object { $_ -and $_ -ne $CoreutilsBin })
    $env:PATH = (@($CoreutilsBin) + $pathEntries) -join ';'
}

#endregion

#region Unix-style helpers

function open {
    <#
    .SYNOPSIS
        Open a path in File Explorer (defaults to the current directory).
    #>
    param([string]$Target = '.')

    Start-Process explorer.exe (Resolve-Path $Target)
}

function touch {
    <#
    .SYNOPSIS
        Update a file's timestamp, or create it if it doesn't exist.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    }
    else {
        New-Item -ItemType File -Path $Path | Out-Null
    }
}

function extract {
    <#
    .SYNOPSIS
        Extract a zip archive into the folder that contains it.
    #>
    param([Parameter(Mandatory)][string]$File)

    Expand-Archive -LiteralPath $File -DestinationPath (Split-Path $File -Parent) -Force
}

function which {
    <#
    .SYNOPSIS
        Print the full path of a command, like the Unix `which`.
    #>
    param([Parameter(Mandatory)][string]$Command)

    Get-Command $Command | Select-Object -ExpandProperty Path
}

#endregion

#region Audio transcription

function Invoke-Transcription {
    <#
    .SYNOPSIS
        Transcribe an audio file to text using OpenAI Whisper (CUDA).

    .DESCRIPTION
        Runs Whisper on the GPU and reports live progress by parsing the
        timestamps in its output against the file's total duration (via ffprobe).
        The finished transcript is moved to the requested output path.

    .PARAMETER File
        Path to the audio file to transcribe.

    .PARAMETER Output
        Destination text file. Defaults to the input path with a .txt extension.

    .PARAMETER Model
        Whisper model to use (e.g. tiny, base, small, medium, large). Default: medium.

    .PARAMETER Timestamps
        Include per-word timestamps in the transcript.

    .EXAMPLE
        transcribe interview.m4a
        transcribe lecture.mp3 -Model large -Timestamps

    .NOTES
        Requires whisper and ffprobe on PATH, plus a CUDA-capable GPU.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$File,
        [string]$Output = ([System.IO.Path]::ChangeExtension($File, 'txt')),
        [string]$Model = 'medium',
        [switch]$Timestamps
    )

    $tempDir = [System.IO.Path]::GetTempPath()
    $tsValue = if ($Timestamps) { 'True' } else { 'False' }
    $duration = [double](& ffprobe -v quiet -show_entries format=duration -of csv=p=0 $File 2>$null)
    $env:PYTHONUNBUFFERED = '1'

    & whisper $File --model $Model --device cuda --output_dir $tempDir `
        --output_format txt --verbose True --word_timestamps $tsValue 2>&1 |
    ForEach-Object {
        $line = $_.ToString()
        if ($duration -gt 0 -and $line -match '\[[\d:.]+ --> ([\d:.]+)\]') {
            $parts = $matches[1] -split '[:\.]'
            $secs = if ($parts.Count -eq 4) {
                [int]$parts[0] * 3600 + [int]$parts[1] * 60 + [int]$parts[2] + [int]$parts[3] / 1000.0
            }
            else {
                [int]$parts[0] * 60 + [int]$parts[1] + [int]$parts[2] / 1000.0
            }
            $pct = [math]::Min(100, [math]::Round($secs / $duration * 100))
            Write-Progress -Activity 'Transcribing' -Status "$pct%" -PercentComplete $pct
        }
    }

    Write-Progress -Activity 'Transcribing' -Completed

    $inputBase = [System.IO.Path]::GetFileNameWithoutExtension($File)
    Move-Item (Join-Path $tempDir "$inputBase.txt") $Output -Force
    Write-Host "Done -> $Output"
}

Set-Alias transcribe Invoke-Transcription

function skills {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if ($Command -eq "add") {
        if ($Args.Count -eq 0) {
            Write-Host "Usage: skills add <path>" -ForegroundColor Red
            return
        }

        $SkillPath = $Args[0] -replace '^["'']|["'']$'  # Remove quotes if present

        # Resolve to full path
        $FullPath = Resolve-Path -Path $SkillPath -ErrorAction SilentlyContinue
        if (-not $FullPath) {
            Write-Host "Error: Path not found: $SkillPath" -ForegroundColor Red
            return
        }

        $FullPath = $FullPath.Path

        # Check if it's a directory with SKILL.md
        if ((Test-Path -Path $FullPath -PathType Container)) {
            $SkillFile = Join-Path $FullPath "SKILL.md"
            if (-not (Test-Path $SkillFile)) {
                Write-Host "Error: SKILL.md not found in $FullPath" -ForegroundColor Red
                return
            }
            $SourceDir = $FullPath
        }
        # Check if it's a .skill or .zip file (try to extract)
        elseif ($FullPath -match '\.(skill|zip)$' -and (Test-Path -Path $FullPath -PathType Leaf)) {
            Write-Host "Extracting archive..." -ForegroundColor Cyan
            $TempDir = New-TemporaryDirectory
            Expand-Archive -Path $FullPath -DestinationPath $TempDir -Force

            $SkillFile = Join-Path $TempDir "SKILL.md"
            if (-not (Test-Path $SkillFile)) {
                # SKILL.md may be inside a single top-level folder in the archive
                $SubDirs = Get-ChildItem -Path $TempDir -Directory
                if ($SubDirs.Count -eq 1 -and (Test-Path (Join-Path $SubDirs[0].FullName "SKILL.md"))) {
                    $SourceDir = $SubDirs[0].FullName
                }
                else {
                    Write-Host "Error: SKILL.md not found in archive" -ForegroundColor Red
                    Remove-Item -Path $TempDir -Recurse -Force
                    return
                }
            }
            else {
                $SourceDir = $TempDir
            }
        }
        else {
            Write-Host "Error: Must be a directory containing SKILL.md or a .skill/.zip archive file" -ForegroundColor Red
            return
        }

        # Extract skill name from SKILL.md frontmatter
        $Content = Get-Content -Path (Join-Path $SourceDir "SKILL.md") -Raw
        if ($Content -match 'name:\s*([^\n\r]+)') {
            $SkillName = $Matches[1].Trim()
        }
        else {
            $SkillName = Split-Path -Leaf $SourceDir
        }

        # Prompt for scope
        Write-Host "`nWhere do you want to install '$SkillName'?" -ForegroundColor Cyan
        Write-Host "1) Globally (~/.copilot/skills/ or ~/.agents/skills/)"
        Write-Host "2) Project (./.github/skills/ or ./.agents/skills/)"
        Write-Host ""
        $Choice = Read-Host "Enter choice (1 or 2)"

        $DestDir = $null

        if ($Choice -eq "1") {
            $GlobalDir = Join-Path $env:USERPROFILE ".copilot" "skills" $SkillName
            New-Item -Path (Split-Path $GlobalDir) -ItemType Directory -Force | Out-Null
            Copy-Item -Path $SourceDir -Destination $GlobalDir -Recurse -Force
            $DestDir = $GlobalDir
            Write-Host "✓ Installed: $GlobalDir" -ForegroundColor Green
        }
        elseif ($Choice -eq "2") {
            # Try different project root markers
            $ProjectRoot = Get-Location
            $Found = $false

            while ($ProjectRoot.Path -ne $ProjectRoot.Drive.Name) {
                if ((Test-Path (Join-Path $ProjectRoot ".git")) -or
                    (Test-Path (Join-Path $ProjectRoot ".github")) -or
                    (Test-Path (Join-Path $ProjectRoot "package.json"))) {
                    $Found = $true
                    break
                }
                $ProjectRoot = Split-Path $ProjectRoot
            }

            if (-not $Found) {
                Write-Host "Error: Could not find project root" -ForegroundColor Red
                if ($SourceDir -like "$env:TEMP*") {
                    Remove-Item -Path $SourceDir -Recurse -Force
                }
                return
            }

            $ProjectSkillsDir = Join-Path $ProjectRoot ".github" "skills" $SkillName
            New-Item -Path (Split-Path $ProjectSkillsDir) -ItemType Directory -Force | Out-Null
            Copy-Item -Path $SourceDir -Destination $ProjectSkillsDir -Recurse -Force
            $DestDir = $ProjectSkillsDir
            Write-Host "✓ Installed: $ProjectSkillsDir" -ForegroundColor Green
        }
        else {
            Write-Host "Invalid choice. Cancelled." -ForegroundColor Red
        }

        # Cleanup temp directory if it was extracted
        if ($SourceDir -like "$env:TEMP*") {
            Remove-Item -Path $SourceDir -Recurse -Force
        }

        if ($DestDir) {
            Write-Host "`nInstalled to: $DestDir" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Write-Host "Usage: skills add <path>" -ForegroundColor Gray
    }
}

# Helper function for PowerShell 6 compatibility
function New-TemporaryDirectory {
    $Parent = [System.IO.Path]::GetTempPath()
    $Name = [System.IO.Path]::GetRandomFileName()
    New-Item -ItemType Directory -Path (Join-Path $Parent $Name)
}

# Compress a directory to a zip file, excluding files matched by .gitignore
function Compress-WithGitignore {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$DestinationPath
    )

    $Path = (Resolve-Path $Path).Path
    if (-not (Test-Path $Path -PathType Container)) {
        Write-Host "Error: '$Path' is not a directory" -ForegroundColor Red
        return
    }

    if (-not $DestinationPath) {
        $DestinationPath = Join-Path (Split-Path $Path -Parent) ("{0}.zip" -f (Split-Path $Path -Leaf))
    }

    if (Test-Path $DestinationPath) {
        Remove-Item -Path $DestinationPath -Force
    }

    Push-Location $Path
    try {
        if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $Path ".gitignore"))) {
            # Use git to list files not excluded by .gitignore (includes untracked, excludes ignored)
            $Files = git ls-files --cached --others --exclude-standard 2>$null
        }
        else {
            Write-Host "Warning: git or .gitignore not found, including all files" -ForegroundColor Yellow
            $Files = Get-ChildItem -Path $Path -Recurse -File | ForEach-Object {
                [System.IO.Path]::GetRelativePath($Path, $_.FullName)
            }
        }

        if (-not $Files) {
            Write-Host "Error: No files to compress" -ForegroundColor Red
            return
        }

        # Stage files in a temp directory preserving relative structure, then compress
        $StagingDir = New-TemporaryDirectory
        try {
            foreach ($File in $Files) {
                $SourceFile = Join-Path $Path $File
                if (Test-Path $SourceFile -PathType Leaf) {
                    $TargetFile = Join-Path $StagingDir.FullName $File
                    New-Item -Path (Split-Path $TargetFile -Parent) -ItemType Directory -Force | Out-Null
                    Copy-Item -Path $SourceFile -Destination $TargetFile -Force
                }
            }
            Compress-Archive -Path (Join-Path $StagingDir.FullName "*") -DestinationPath $DestinationPath -Force
            Write-Host "✓ Created: $DestinationPath" -ForegroundColor Green
        }
        finally {
            Remove-Item -Path $StagingDir.FullName -Recurse -Force
        }
    }
    finally {
        Pop-Location
    }
}


#endregion
