<#
    Microsoft.PowerShell_profile.ps1

    Personal PowerShell profile: console setup, Unix-style helper functions,
    and PSReadLine quality-of-life tweaks. Designed to be safe to load on a
    fresh machine — missing modules are installed on first launch.

    Compatible with Windows PowerShell 5.1+.
#>

#region Console

# Use UTF-8 for input and output so emoji, accents, and box-drawing render correctly.
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

#endregion

#region Functions

function open {
    <#
    .SYNOPSIS
        Opens a path in its default handler.
    .DESCRIPTION
        Files launch in their default app; folders open in Explorer.
        Defaults to the current directory. Accepts pipeline input.
    .PARAMETER target
        The file or folder path to open. Defaults to the current directory.
    .EXAMPLE
        open report.pdf
    .EXAMPLE
        "a.txt", "b.txt" | open
    #>
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$target = "."
    )

    process {
        $path = Resolve-Path -LiteralPath $target -ErrorAction SilentlyContinue
        if (-not $path) {
            Write-Error "Path not found: $target"
            return
        }
        Invoke-Item -LiteralPath $path
    }
}

function touch {
    <#
    .SYNOPSIS
        Updates a file's timestamp, creating it if it doesn't exist.
    .DESCRIPTION
        Mirrors the Unix `touch`. Accepts multiple paths and pipeline input.
    .EXAMPLE
        touch newfile.txt
    .EXAMPLE
        "a.txt", "b.txt" | touch
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Path
    )

    process {
        foreach ($p in $Path) {
            if (Test-Path -LiteralPath $p) {
                (Get-Item -LiteralPath $p).LastWriteTime = Get-Date
            } else {
                New-Item -ItemType File -Path $p | Out-Null
            }
        }
    }
}

function extract {
    <#
    .SYNOPSIS
        Extracts a .zip archive into a folder named after the archive.
    .DESCRIPTION
        Wraps Expand-Archive. Each archive is extracted into a subfolder
        (next to it) named after the archive, so contents aren't scattered.
        Accepts multiple paths and pipeline input.
    .EXAMPLE
        extract release.zip
    .EXAMPLE
        Get-ChildItem *.zip | extract
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$File
    )

    process {
        foreach ($f in $File) {
            $path = Resolve-Path -LiteralPath $f -ErrorAction SilentlyContinue
            if (-not $path) {
                Write-Error "Archive not found: $f"
                continue
            }
            $name = [System.IO.Path]::GetFileNameWithoutExtension($path.Path)
            $dest = Join-Path (Split-Path $path.Path -Parent) $name
            Expand-Archive -LiteralPath $path.Path -DestinationPath $dest -Force
        }
    }
}

function which {
    <#
    .SYNOPSIS
        Shows where a command resolves, like the Unix `which`.
    .DESCRIPTION
        Prints the executable path for external programs, and falls back to the
        resolved definition for aliases, functions, and cmdlets (which have no
        file path). Accepts multiple commands and pipeline input.
    .EXAMPLE
        which git
    .EXAMPLE
        "git", "code" | which
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Command
    )

    process {
        foreach ($c in $Command) {
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if (-not $cmd) {
                Write-Error "Command not found: $c"
                continue
            }
            if ($cmd.Path) { $cmd.Path } else { $cmd.Definition }
        }
    }
}

#endregion

#region PSReadLine

# Show parameter tooltips inline while typing completions.
Set-PSReadLineOption -ShowToolTips:$true
# Silence the terminal bell (no beep/flash on errors or unmatched completions).
Set-PSReadLineOption -BellStyle None

#endregion

#region Modules

# CompletionPredictor: provides IntelliSense-style command predictions in PSReadLine,
# suggesting completions inline as you type based on command history and context.
# Installed automatically on first launch if it isn't already present.
try {
    Import-Module CompletionPredictor -ErrorAction Stop
}
catch {
    Write-Host "CompletionPredictor module not found. Installing..." -ForegroundColor Yellow
    Install-Module CompletionPredictor -Scope CurrentUser -Force -AcceptLicense
    Import-Module CompletionPredictor
    Write-Host "CompletionPredictor installed and loaded." -ForegroundColor Green
}

#endregion
