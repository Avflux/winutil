function Uninstall-WinUtilGitHubPackage {
    <#

    .SYNOPSIS
        Removes the GitHub packages WinUtil installed.

    .DESCRIPTION
        Removal follows the record written at install time: a zip is removed with its install
        directory, and an msi or exe through the uninstall entry its installer registered. A
        package with no record was not installed through this source, so its removal is not
        guessed at.

        Emits one result object per package, matching the shape the other installers use.

    .PARAMETER Action
        The action to perform. Only Uninstall is supported.

    .PARAMETER Packages
        Application config entries carrying the github owner/repo pair.

    #>

    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Uninstall")]
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [PSObject[]]$Packages
    )

    $state = Get-WinUtilGitHubPackageState

    foreach ($package in $Packages) {
        $repository = [string]$package.github
        if ([string]::IsNullOrWhiteSpace($repository)) {
            continue
        }

        $exitCode = -1
        $outcome = "Failed"
        $detail = "no result"

        try {
            $record = $state[$repository]
            if (-not $record) {
                $outcome = "Skipped"
                $detail = "not installed through the GitHub source"
            } elseif ([string]$record.Type -eq "zip") {
                $installDirectory = [string]$record.InstallDirectory
                if (-not [string]::IsNullOrWhiteSpace($installDirectory) -and (Test-Path -LiteralPath $installDirectory)) {
                    Remove-Item -LiteralPath $installDirectory -Recurse -Force -ErrorAction Stop
                }
                $exitCode = 0
                $outcome = "Succeeded"
                $detail = "install directory removed"
            } else {
                $command = [string]$record.UninstallCommand
                if ([string]::IsNullOrWhiteSpace($command)) {
                    throw "No uninstall command was recorded for ${repository}; remove it from Installed apps"
                }

                $exitCode = Invoke-WinUtilGitHubUninstaller -Command $command
                if ($exitCode -eq 0) {
                    $outcome = "Succeeded"
                    $detail = "exit code 0"
                } elseif ($exitCode -in @(3010, 1641)) {
                    $outcome = "Succeeded"
                    $detail = "uninstalled, a restart is needed to finish"
                } elseif ($exitCode -eq 1605) {
                    $outcome = "Skipped"
                    $detail = "the product is not installed"
                } else {
                    $detail = "uninstaller exited with code $exitCode"
                }
            }
        } catch {
            $detail = $_.Exception.Message
        }

        if ($outcome -ne "Failed") {
            Remove-WinUtilGitHubPackageRecord -Repository $repository
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

function Invoke-WinUtilGitHubUninstaller {
    <#

    .SYNOPSIS
        Runs the uninstall command recorded for a GitHub package.

    .DESCRIPTION
        An msi registers "MsiExec.exe /X{guid}", and running msiexec directly is what allows the
        silent flags to be appended rather than embedded in a cmd.exe command line. Anything else
        is the application's own uninstall command, which Windows only exposes as a command line,
        so it goes through the command processor.

    .PARAMETER Command
        The uninstall command recorded at install time.

    .OUTPUTS
        System.Int32 - the uninstaller exit code.

    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )

    if ($Command -match '(?i)^\s*"?msiexec(?:\.exe)?"?\s+/[xX]\s*(\{[0-9A-Fa-f-]+\}|\S+)') {
        $process = Start-Process msiexec.exe -ArgumentList "/x $($Matches[1]) /qn /norestart" -Wait -PassThru
        return $process.ExitCode
    }

    $process = Start-Process -FilePath $env:ComSpec -ArgumentList "/c", $Command -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode
}
