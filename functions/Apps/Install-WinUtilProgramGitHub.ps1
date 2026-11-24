function Install-WinUtilProgramGitHub {
    <#

    .SYNOPSIS
        Installs applications whose only distribution channel is a GitHub release.

    .DESCRIPTION
        Downloads the asset the resolver picked into a temporary file, verifies the SHA256 the
        release publishes when there is one, and runs it: msiexec for an msi, the executable
        itself for an exe, and an extract into the per-user install directory for a zip.

        Emits one result object per package with the same fields the WinGet and Chocolatey
        installers emit, so the caller's reporting needs no special case.

    .PARAMETER Action
        The action to perform. Only Install is supported for now.

    .PARAMETER Packages
        Application config entries carrying github and, optionally, githubAsset, githubType,
        githubArgs and githubBin.

    .NOTES
        A release without a published digest is installed with a warning rather than refused:
        older releases predate the digest field, and refusing them would leave those apps with
        no install path at all. A digest that is published and does not match is always fatal.

    #>

    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Install")]
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [PSObject[]]$Packages
    )

    # The installer worked and wants a restart to finish
    $rebootExitCodes = @{
        3010 = "installed, a restart is needed to finish"
        1641 = "installed, the installer started a restart"
    }

    $state = Get-WinUtilGitHubPackageState

    foreach ($package in $Packages) {
        $repository = [string]$package.github
        if ([string]::IsNullOrWhiteSpace($repository)) {
            continue
        }

        $exitCode = -1
        $outcome = "Failed"
        $detail = "no result"
        $downloadPath = $null
        $installDirectory = $null
        $uninstallSnapshot = $null

        try {
            $release = Resolve-WinUtilGitHubRelease -Repository $repository -AssetPattern $package.githubAsset
            $record = $state[$repository]
            if ($record -and
                ([string]$record.Version) -eq $release.Version -and
                (Test-WinUtilGitHubPackageInstalled -Record $record)) {
                # Running the installer over a working install is what makes an already
                # installed msi or exe fail, so a present install at this version is done
                $exitCode = 0
                $outcome = "Skipped"
                $detail = "already installed ($($release.Version))"
            } else {
                $assetExtension = [System.IO.Path]::GetExtension($release.AssetName).ToLowerInvariant()

                $type = [string]$package.githubType
                if ([string]::IsNullOrWhiteSpace($type)) {
                    $type = $assetExtension.TrimStart(".")
                }
                $type = $type.ToLowerInvariant()
                if ($type -notin @("msi", "exe", "zip")) {
                    throw "Unsupported GitHub asset type '$type' for $($release.AssetName)"
                }

                $downloadPath = Join-Path ([System.IO.Path]::GetTempPath()) ("WinUtilGitHub-" + [guid]::NewGuid().ToString("N") + $assetExtension)
                Write-WinUtilLog -Component "Package" -Message "$Action GitHub package: $repository ($($release.Version), $($release.AssetName))"

                Invoke-WebRequest -Uri $release.DownloadUrl -OutFile $downloadPath -UseBasicParsing -TimeoutSec 300

                if ($release.Digest) {
                    $hash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
                    if (-not $hash.Equals([string]$release.Digest, [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "SHA256 verification failed for $repository $($release.Version): the download does not match the published digest"
                    }
                } else {
                    Write-WinUtilLog -Level "WARN" -Component "Package" -Message "$repository $($release.Version) publishes no SHA256 digest; installing the download unverified."
                }

                # An msi registers its product code and an exe its own uninstall command; neither is
                # knowable before the installer runs, so the uninstall keys are diffed around it
                if ($type -in @("msi", "exe")) {
                    $uninstallSnapshot = Get-WinUtilGitHubUninstallSnapshot
                }

                switch ($type) {
                    "msi" {
                        $arguments = if ([string]::IsNullOrWhiteSpace($package.githubArgs)) {
                            "/i `"$downloadPath`" /qn /norestart"
                        } else {
                            "/i `"$downloadPath`" $($package.githubArgs)"
                        }
                        $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
                        $exitCode = $process.ExitCode
                    }
                    "exe" {
                        $startArguments = @{
                            FilePath = $downloadPath
                            Wait     = $true
                            PassThru = $true
                        }
                        if (-not [string]::IsNullOrWhiteSpace($package.githubArgs)) {
                            $startArguments["ArgumentList"] = [string]$package.githubArgs
                        }
                        $process = Start-Process @startArguments
                        $exitCode = $process.ExitCode
                    }
                    "zip" {
                        $installDirectory = Get-WinUtilGitHubInstallDirectory -Repository $repository
                        Expand-WinUtilGitHubArchive -Path $downloadPath -Destination $installDirectory

                        if (-not [string]::IsNullOrWhiteSpace($package.githubBin)) {
                            $binary = Join-Path $installDirectory ([string]$package.githubBin)
                            if (-not (Test-Path -LiteralPath $binary)) {
                                throw "The archive does not contain the configured binary '$($package.githubBin)'"
                            }
                        }
                        $exitCode = 0
                    }
                }

                if ($exitCode -eq 0) {
                    $outcome = "Succeeded"
                    $detail = if ($type -eq "zip") { "extracted to $installDirectory" } else { "exit code 0" }
                } elseif ($rebootExitCodes.ContainsKey($exitCode)) {
                    $outcome = "Succeeded"
                    $detail = $rebootExitCodes[$exitCode]
                } else {
                    $detail = "installer exited with code $exitCode"
                }

                if ($outcome -eq "Succeeded") {
                    $uninstallKey = $null
                    $uninstallCommand = $null
                    $recordDirectory = $null
                    if ($type -eq "zip") {
                        $recordDirectory = $installDirectory
                    }
                    if ($uninstallSnapshot) {
                        $uninstallEntry = Get-WinUtilGitHubNewUninstallEntry -Before $uninstallSnapshot
                        if ($uninstallEntry) {
                            $uninstallKey = $uninstallEntry.UninstallKey
                            $uninstallCommand = if ([string]::IsNullOrWhiteSpace($uninstallEntry.QuietUninstallString)) {
                                $uninstallEntry.UninstallString
                            } else {
                                $uninstallEntry.QuietUninstallString
                            }
                        }
                    }

                    try {
                        Set-WinUtilGitHubPackageRecord -Repository $repository -Record ([pscustomobject]@{
                            Repository       = $repository
                            Version          = $release.Version
                            AssetName        = $release.AssetName
                            Digest           = $release.Digest
                            Type             = $type
                            InstallDirectory = $recordDirectory
                            UninstallKey     = $uninstallKey
                            UninstallCommand = $uninstallCommand
                            InstalledAt      = (Get-Date).ToString("o")
                        })
                    } catch {
                        Write-WinUtilLog -Level "WARN" -Component "Package" -Message "Installed $repository but could not record it: $($_.Exception.Message)"
                    }
                }
            }
        } catch {
            $detail = $_.Exception.Message
        } finally {
            if ($downloadPath -and (Test-Path -LiteralPath $downloadPath)) {
                Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
            }
        }

        $level = if ($outcome -eq "Failed") { "ERROR" } else { "INFO" }
        Write-WinUtilLog -Level $level -Component "Package" -Message "$Action GitHub package $($outcome.ToLowerInvariant()): $repository ($detail)"

        [pscustomobject]@{
            Package  = $repository
            Manager  = "github"
            Action   = $Action
            ExitCode = $exitCode
            Outcome  = $outcome
            Detail   = $detail
        }
    }
}

function Get-WinUtilGitHubInstallDirectory {
    <#

    .SYNOPSIS
        Returns where a zip-based GitHub package is installed.

    .DESCRIPTION
        Zip releases are portable builds with no installer of their own, so WinUtil extracts
        them into a per-user directory named after the repository. The slash in owner/repo
        cannot appear in a single directory name, so it and the other characters Windows
        forbids are folded to underscores.

    .PARAMETER Repository
        The owner/repo pair.

    .OUTPUTS
        System.String - the install directory for the repository.

    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$Repository
    )

    $name = $Repository -replace '[\\/:*?"<>|]', "_"
    return Join-Path $env:LOCALAPPDATA (Join-Path "winutil\github" $name)
}

function Expand-WinUtilGitHubArchive {
    <#

    .SYNOPSIS
        Extracts a downloaded zip release into its install directory.

    .DESCRIPTION
        Every member is checked against the install directory before anything is written. A
        release is third-party input: an absolute member or one climbing out with .. would
        otherwise place files anywhere the elevated process can write.

    .PARAMETER Path
        The downloaded archive.

    .PARAMETER Destination
        The install directory. Created when missing.

    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$Destination
    )

    if (-not ("System.IO.Compression.ZipFile" -as [type])) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    $root = [System.IO.Path]::GetFullPath($Destination)
    $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrWhiteSpace($entry.FullName)) {
                continue
            }
            if ([System.IO.Path]::IsPathRooted($entry.FullName)) {
                throw "Archive member '$($entry.FullName)' is an absolute path"
            }
            $target = [System.IO.Path]::GetFullPath((Join-Path $root $entry.FullName))
            if (-not $target.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Archive member '$($entry.FullName)' resolves outside the install directory"
            }
        }
    } finally {
        $archive.Dispose()
    }

    Expand-Archive -LiteralPath $Path -DestinationPath $root -Force
}
