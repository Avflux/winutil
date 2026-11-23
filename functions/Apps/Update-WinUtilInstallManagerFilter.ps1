function Test-WinUtilAppMatchesPackageManager {
    <#

    .SYNOPSIS
        Tells whether the selected package manager can install an app

    .DESCRIPTION
        Each entry in config/applications.json names the sources it can be installed from.
        An app whose entry has no id for the selected manager cannot be installed by it, so
        the Install tab hides it instead of offering an install that would do nothing.

        "na" is the config's marker for "no id for this manager", not a package named na.

    .PARAMETER App
        The application entry from config/applications.json.

    .PARAMETER Preference
        The selected package manager: Winget, Choco, or GitHub.

    .OUTPUTS
        System.Boolean - true when the app has a source for that manager.

    #>

    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$App,

        [Parameter(Mandatory = $false)]
        [string]$Preference = $sync.preferences.packagemanager
    )

    if ($null -eq $App) {
        return $false
    }

    # No manager has been chosen (an unset or imported preference): nothing to filter by
    if ([string]::IsNullOrWhiteSpace($Preference)) {
        return $true
    }

    switch ($Preference) {
        "Choco" {
            $id = [string]$App.choco
            return (-not [string]::IsNullOrWhiteSpace($id) -and $id -ne "na")
        }
        "GitHub" {
            return -not [string]::IsNullOrWhiteSpace([string]$App.github)
        }
        default {
            $id = [string]$App.winget
            return (-not [string]::IsNullOrWhiteSpace($id) -and $id -ne "na")
        }
    }
}

function Update-WinUtilInstallManagerFilter {
    <#

    .SYNOPSIS
        Re-applies the Install tab filters for the selected package manager

    .DESCRIPTION
        The package manager is a third filter next to the search text and the category chips,
        so switching it re-runs the one walk that decides visibility. Hiding rows here instead
        would let a later search put back an app the manager cannot install.

    #>

    param()

    if ($null -eq $sync -or $null -eq $sync.ItemsControl -or $null -eq $sync.configs -or $null -eq $sync.configs.applicationsHashtable) {
        return
    }

    $searchText = if ($null -ne $sync.SearchBar) { [string]$sync.SearchBar.Text } else { "" }
    $categories = if ($null -ne $sync.SelectedAppCategories) { $sync.SelectedAppCategories.ToArray() } else { @() }

    Find-AppsByNameOrDescription -SearchString $searchText -Categories $categories
}
