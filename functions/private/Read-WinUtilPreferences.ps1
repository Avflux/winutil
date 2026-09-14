function Read-WinUtilPreferences {

    <#

    .SYNOPSIS
        Loads previously saved user preferences from a local JSON file.

    .DESCRIPTION
        Reads $sync.winutildir/preferences.json and populates $sync.preferences with
        the saved values. Missing or invalid files are silently ignored.

    #>

    if (-not $sync.winutildir) { return }

    $prefsFile = Join-Path $sync.winutildir "preferences.json"
    if (-not (Test-Path -LiteralPath $prefsFile)) { return }

    try {
        $raw = [System.IO.File]::ReadAllText($prefsFile)
        $data = $raw | ConvertFrom-Json

        if ($data.language)       { $sync.preferences.language = [string]$data.language }
        if ($data.theme)          { $sync.preferences.theme = [string]$data.theme }
        if ($data.packagemanager) { $sync.preferences.packagemanager = [string]$data.packagemanager }
    } catch {
        # Corrupted file — ignore and keep defaults.
    }
}
