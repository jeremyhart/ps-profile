<#
    install.ps1

    Downloads the PowerShell profile into $PROFILE and loads it into the
    current session. Safe to run on a fresh machine — the profile folder is
    created if it doesn't already exist.

    Also installs Microsoft Coreutils for Windows if it isn't already present,
    and adds its bin folder to the user PATH (winget does not do this itself).

    If a profile is already present, you're asked whether to overwrite it or
    merge (append) this profile onto the end of it. The previous profile is
    always backed up first.

    Usage:
        irm https://raw.githubusercontent.com/jeremyhart/ps-profile/main/install.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

$url = 'https://raw.githubusercontent.com/jeremyhart/ps-profile/main/Microsoft.PowerShell_profile.ps1'
$CoreutilsBin = Join-Path $env:ProgramFiles 'coreutils\bin'

#region Coreutils

function Install-Coreutils {
    <#
    .SYNOPSIS
        Install Microsoft Coreutils for Windows if it isn't already present.

    .DESCRIPTION
        Coreutils installs to "C:\Program Files\coreutils\bin". winget does not
        add that folder to PATH, so this adds it to the user PATH as well as the
        current session.

        Installing into Program Files needs an elevated session. If this session
        isn't elevated, the install is skipped with a warning rather than failing
        the whole script — the profile leaves the built-in aliases alone when
        coreutils is missing, so the shell still works.
    #>
    param([Parameter(Mandatory)][string]$BinPath)

    if (Test-Path $BinPath) {
        Write-Host "Coreutils already installed at $BinPath" -ForegroundColor DarkGray
    }
    else {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Warning "winget not found - skipping coreutils install. Install it manually from https://github.com/microsoft/coreutils/releases"
            return
        }

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Warning "Coreutils is not installed, and this session isn't elevated."
            Write-Warning "Re-run this installer from an admin PowerShell, or run: winget install --id Microsoft.Coreutils"
            return
        }

        Write-Host "Installing Microsoft Coreutils..." -ForegroundColor Cyan

        # --source winget avoids the msstore source agreement prompt.
        winget install --id Microsoft.Coreutils --exact --source winget `
            --accept-package-agreements --accept-source-agreements

        if (-not (Test-Path $BinPath)) {
            Write-Warning "Coreutils install did not produce $BinPath - skipping PATH setup."
            return
        }

        Write-Host "Coreutils installed to $BinPath" -ForegroundColor Green
    }

    # Add to the persisted user PATH so new sessions pick it up.
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ })

    if ($entries -notcontains $BinPath) {
        [Environment]::SetEnvironmentVariable('PATH', (@($BinPath) + $entries) -join ';', 'User')
        Write-Host "Added $BinPath to your user PATH" -ForegroundColor Green
    }

    # Add to the current session too, so the profile below sees it immediately.
    $sessionEntries = @($env:PATH -split ';' | Where-Object { $_ -and $_ -ne $BinPath })
    $env:PATH = (@($BinPath) + $sessionEntries) -join ';'
}

# Run before the profile is loaded, so the alias-stripping in the profile
# has something to fall through to in this same session.
Install-Coreutils -BinPath $CoreutilsBin

#endregion

#region Profile

# Ensure the profile directory exists (it may be missing on a clean machine).
New-Item -ItemType Directory -Force (Split-Path $PROFILE) | Out-Null

# Fetch the profile contents up front so we can either overwrite or append.
$content = Invoke-RestMethod $url

if (Test-Path $PROFILE) {
    # Back up the current profile before changing anything.
    $backup = "$PROFILE.bak"
    Copy-Item $PROFILE $backup -Force
    Write-Host "Existing profile backed up to $backup" -ForegroundColor DarkGray

    $marker = '# ----- Appended by jeremyhart/ps-profile -----'

    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Overwrite', 'Replace the existing profile entirely.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&Merge', 'Append this profile to the end of the existing one.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&Cancel', 'Make no changes and exit.')
    )
    $decision = $Host.UI.PromptForChoice(
        'An existing PowerShell profile was found',
        "What would you like to do with $PROFILE?",
        $choices,
        0)

    switch ($decision) {
        0 {
            Set-Content -Path $PROFILE -Value $content -Encoding UTF8
            Write-Host "Profile overwritten at $PROFILE" -ForegroundColor Green
        }
        1 {
            if ((Get-Content $PROFILE -Raw) -match [regex]::Escape($marker)) {
                Write-Host "This profile was already merged in previously - skipping to avoid duplicates." -ForegroundColor Yellow
            }
            else {
                Add-Content -Path $PROFILE -Value ("`n`n$marker`n" + $content) -Encoding UTF8
                Write-Host "Profile merged into $PROFILE" -ForegroundColor Green
            }
        }
        2 {
            Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
            return
        }
    }
}
else {
    Set-Content -Path $PROFILE -Value $content -Encoding UTF8
    Write-Host "Profile installed to $PROFILE" -ForegroundColor Green
}

# Load it into the current session so it takes effect immediately.
. $PROFILE
Write-Host "Profile loaded and ready to use." -ForegroundColor Green

#endregion
