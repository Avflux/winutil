function Get-WinUtilGitHubStatePath {
    <#

    .SYNOPSIS
        Returns where WinUtil records the GitHub packages it installed.

    .OUTPUTS
        System.String - the state file path.

    #>

    param()

    return Join-Path $env:LOCALAPPDATA "winutil\github-packages.json"
}

function Get-WinUtilGitHubPackageState {
    <#

    .SYNOPSIS
        Reads the GitHub package records.

    .DESCRIPTION
        Only this machine knows what WinUtil installed for a GitHub release, at which version,
        and how to remove it, so those records live beside the log rather than in the config.
        A missing file is an empty state; a file that cannot be read is reported and treated as
        empty, because a damaged record must not block installing or detecting apps.

    .OUTPUTS
        System.Collections.Hashtable keyed by owner/repo.

    #>

    param()

    $state = @{}
    $path = Get-WinUtilGitHubStatePath

    if (-not (Test-Path -LiteralPath $path)) {
        return $state
    }

    try {
        $data = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($property in $data.PSObject.Properties) {
            $state[$property.Name] = $property.Value
        }
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "Package" -Message "Ignoring unreadable GitHub package state at ${path}: $($_.Exception.Message)"
        $state = @{}
    }

    return $state
}

function Save-WinUtilGitHubPackageState {
    <#

    .SYNOPSIS
        Writes the GitHub package records.

    .DESCRIPTION
        The records are written beside the real file and moved into place, so an interrupted
        write cannot leave a truncated state that reads back as empty.

    .PARAMETER State
        The records keyed by owner/repo.

    #>

    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$State
    )

    $path = Get-WinUtilGitHubStatePath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporary = "$path.tmp"
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Set-WinUtilGitHubPackageRecord {
    <#

    .SYNOPSIS
        Adds or replaces the record for one repository.

    .PARAMETER Repository
        The owner/repo pair.

    .PARAMETER Record
        The record written at install time.

    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$Repository,

        [Parameter(Mandatory=$true)]
        $Record
    )

    $state = Get-WinUtilGitHubPackageState
    $state[$Repository] = $Record
    Save-WinUtilGitHubPackageState -State $state
}

function Remove-WinUtilGitHubPackageRecord {
    <#

    .SYNOPSIS
        Drops the record for one repository.

    .PARAMETER Repository
        The owner/repo pair.

    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$Repository
    )

    $state = Get-WinUtilGitHubPackageState
    if (-not $state.ContainsKey($Repository)) {
        return
    }

    $state.Remove($Repository)
    Save-WinUtilGitHubPackageState -State $state
}

function Test-WinUtilGitHubPackageInstalled {
    <#

    .SYNOPSIS
        Tells whether a recorded GitHub package is still present.

    .DESCRIPTION
        A zip is present while its install directory exists; an msi or exe while the uninstall
        entry its installer registered still exists. A record with neither was installed by an
        installer that registered nothing, so its presence cannot be verified here.

    .PARAMETER Record
        The record read from the state file.

    .OUTPUTS
        System.Boolean

    #>

    param(
        [Parameter(Mandatory=$true)]
        $Record
    )

    $installDirectory = [string]$Record.InstallDirectory
    if (-not [string]::IsNullOrWhiteSpace($installDirectory)) {
        return Test-Path -LiteralPath $installDirectory
    }

    $uninstallKey = [string]$Record.UninstallKey
    if (-not [string]::IsNullOrWhiteSpace($uninstallKey)) {
        return Test-Path -LiteralPath $uninstallKey
    }

    return $false
}
