function Save-WinUtilPreferences {

    <#

    .SYNOPSIS
        Persists user preferences to a local JSON file.

    .DESCRIPTION
        Saves the current preference values from $sync.preferences to a JSON file in
        $sync.winutildir so they survive across sessions. Only serializable scalar
        values are written; internal hashtable keys and runtime-only state are skipped.

    #>

    if (-not $sync.winutildir) { return }

    $prefsDir = $sync.winutildir
    if (-not (Test-Path -LiteralPath $prefsDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $prefsDir -Force -ErrorAction Stop
        } catch {
            return
        }
    }

    $prefsFile = Join-Path $prefsDir "preferences.json"

    $data = @{}
    if ($sync.preferences.language) { $data.language = $sync.preferences.language }
    if ($sync.preferences.theme)   { $data.theme = $sync.preferences.theme }
    if ($sync.preferences.packagemanager) { $data.packagemanager = $sync.preferences.packagemanager }

    try {
        $json = $data | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($prefsFile, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {
        # Silently ignore — preferences are non-critical.
    }
}
