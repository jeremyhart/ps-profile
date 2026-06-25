<#
    install.ps1

    Downloads the PowerShell profile into $PROFILE and loads it into the
    current session. Safe to run on a fresh machine — the profile folder is
    created if it doesn't already exist.

    If a profile is already present, you're asked whether to overwrite it or
    merge (append) this profile onto the end of it. The previous profile is
    always backed up first.

    Usage:
        irm https://raw.githubusercontent.com/jeremyhart/ps-profile/main/install.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

$url = 'https://raw.githubusercontent.com/jeremyhart/ps-profile/main/Microsoft.PowerShell_profile.ps1'

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
