function Get-WinUtilGitHubUninstallRoots {
    <#

    .SYNOPSIS
        Returns the registry locations where Windows keeps uninstall entries.

    .OUTPUTS
        System.String[] - the uninstall registry roots.

    #>

    param()

    return @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
}

function Get-WinUtilGitHubUninstallSnapshot {
    <#

    .SYNOPSIS
        Captures the uninstall entries present before an installer runs.

    .DESCRIPTION
        An installer does not say up front which uninstall entry it will create: an msi derives
        the product code from its own metadata and an exe writes whatever name it likes. Taking
        the set before the run is what makes the entry the installer adds identifiable after it.

    .OUTPUTS
        System.Collections.Hashtable keyed by each entry's provider path.

    #>

    param()

    $snapshot = @{}
    foreach ($root in Get-WinUtilGitHubUninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $snapshot[[string]$key.PSPath] = $true
        }
    }

    return $snapshot
}

function Get-WinUtilGitHubNewUninstallEntry {
    <#

    .SYNOPSIS
        Finds the uninstall entry an installer added.

    .DESCRIPTION
        Returns the first entry that was not in the snapshot and carries an uninstall command.
        An installer can register helper keys without one, so entries without a command are
        skipped; the caller records the entry and uninstalls through it later.

    .PARAMETER Before
        The snapshot taken with Get-WinUtilGitHubUninstallSnapshot.

    .OUTPUTS
        System.Management.Automation.PSCustomObject, or nothing when the installer registered no
        entry.

    #>

    param(
        [hashtable]$Before
    )

    foreach ($root in Get-WinUtilGitHubUninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $path = [string]$key.PSPath
            if ($Before -and $Before.ContainsKey($path)) {
                continue
            }

            $entry = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
            if ($null -eq $entry) {
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$entry.UninstallString) -and
                [string]::IsNullOrWhiteSpace([string]$entry.QuietUninstallString)) {
                continue
            }

            return [pscustomobject]@{
                UninstallKey        = $path
                DisplayName         = [string]$entry.DisplayName
                UninstallString     = [string]$entry.UninstallString
                QuietUninstallString = [string]$entry.QuietUninstallString
            }
        }
    }
}
