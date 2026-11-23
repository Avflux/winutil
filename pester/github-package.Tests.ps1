#===========================================================================
# Tests - GitHub release source
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    . (Join-Path $script:repoRoot "functions\Apps\Resolve-WinUtilGitHubRelease.ps1")
    . (Join-Path $script:repoRoot "functions\Apps\Install-WinUtilProgramGitHub.ps1")

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Write-WinUtilLog {
        param([string]$Level, [string]$Component, [string]$Message, [switch]$Detail)
    }

    function New-GitHubTestAsset {
        param(
            [string]$Name,
            [string]$Digest,
            [int]$Size = 1024
        )

        [pscustomobject]@{ Name = $Name; Digest = $Digest; Size = $Size }
    }

    function New-GitHubTestRelease {
        param(
            [string]$Tag = "v1.0.0",
            [object[]]$Assets
        )

        [pscustomobject]@{
            tag_name   = $Tag
            prerelease = $false
            assets     = @($Assets | ForEach-Object {
                [pscustomobject]@{
                    name                 = $_.Name
                    browser_download_url = "https://github.com/owner/repo/releases/download/$Tag/$($_.Name)"
                    digest               = $_.Digest
                    size                 = $_.Size
                }
            })
        }
    }

    function New-GitHubInstallPackage {
        param(
            [string]$Repository = "owner/repo",
            [string]$AssetPattern,
            [string]$Type,
            [string]$Arguments,
            [string]$Bin
        )

        [pscustomobject]@{
            github      = $Repository
            githubAsset = $AssetPattern
            githubType  = $Type
            githubArgs  = $Arguments
            githubBin   = $Bin
        }
    }

    function New-GitHubInstallRelease {
        param(
            [string]$AssetName = "tool-x64.msi",
            [string]$Digest,
            [string]$Version = "v1.0.0"
        )

        [pscustomobject]@{
            Repository  = "owner/repo"
            Version     = $Version
            AssetName   = $AssetName
            DownloadUrl = "https://example.test/$AssetName"
            Digest      = $Digest
            Size        = 1
        }
    }
}

Describe "Resolve-WinUtilGitHubRelease" {
    BeforeEach {
        # The cache is what keeps a selection of several apps to one request per repository, so
        # each case starts cold
        $script:WinUtilGitHubReleaseCache = @{}
        $script:savedToken = $env:GITHUB_TOKEN
        $env:GITHUB_TOKEN = ""
    }

    AfterEach {
        $env:GITHUB_TOKEN = $script:savedToken
    }

    It "returns the asset, version and download URL of the latest release" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Tag "v0.44.0" -Assets @(
                New-GitHubTestAsset -Name "lazygit_0.44.0_Windows_x86_64.zip" -Digest "sha256:abc123"
            )
        }

        $result = Resolve-WinUtilGitHubRelease -Repository "jesseduffield/lazygit" -AssetPattern "lazygit_.*_Windows_x86_64\.zip"

        $result.Repository | Should -Be "jesseduffield/lazygit"
        $result.Version | Should -Be "v0.44.0"
        $result.AssetName | Should -Be "lazygit_0.44.0_Windows_x86_64.zip"
        $result.DownloadUrl | Should -Be "https://github.com/owner/repo/releases/download/v0.44.0/lazygit_0.44.0_Windows_x86_64.zip"
        $result.Size | Should -Be 1024
    }

    It "strips the sha256 prefix and normalizes the digest" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(
                New-GitHubTestAsset -Name "tool-x64.msi" -Digest "sha256:ABC123"
            )
        }

        (Resolve-WinUtilGitHubRelease -Repository "owner/repo").Digest | Should -Be "abc123"
    }

    It "returns no digest when the release publishes none" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(New-GitHubTestAsset -Name "tool-x64.msi")
        }

        $result = Resolve-WinUtilGitHubRelease -Repository "owner/repo"

        $result.Digest | Should -BeNullOrEmpty
    }

    It "caches the release so several apps from one repository cost one request" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(New-GitHubTestAsset -Name "tool-x64.msi")
        }

        $first = Resolve-WinUtilGitHubRelease -Repository "owner/repo"
        $second = Resolve-WinUtilGitHubRelease -Repository "owner/repo" -AssetPattern "tool-x64\.msi"

        $second.AssetName | Should -Be $first.AssetName
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It "lists the available assets when the pattern matches nothing" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(
                New-GitHubTestAsset -Name "tool-x64.zip"
                New-GitHubTestAsset -Name "tool-x64.msi"
            )
        }

        { Resolve-WinUtilGitHubRelease -Repository "owner/repo" -AssetPattern "does-not-exist" } |
            Should -Throw "*Available assets: tool-x64.msi, tool-x64.zip*"
    }

    It "prefers the msi installer over an executable or an archive" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(
                New-GitHubTestAsset -Name "tool-x64.zip"
                New-GitHubTestAsset -Name "tool-x64.exe"
                New-GitHubTestAsset -Name "tool-x64.msi"
            )
        }

        (Resolve-WinUtilGitHubRelease -Repository "owner/repo").AssetName | Should -Be "tool-x64.msi"
    }

    It "picks the x64 asset over arm64 for an x64 target" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(
                New-GitHubTestAsset -Name "tool-arm64.zip"
                New-GitHubTestAsset -Name "tool-x64.zip"
            )
        }

        (Resolve-WinUtilGitHubRelease -Repository "owner/repo").AssetName | Should -Be "tool-x64.zip"
    }

    It "refuses to install another architecture's build" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(New-GitHubTestAsset -Name "tool-arm64.zip")
        }

        { Resolve-WinUtilGitHubRelease -Repository "owner/repo" } | Should -Throw "*another architecture*"
    }

    It "accepts an architecture-less installer when no arch-specific asset exists" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(New-GitHubTestAsset -Name "Tool-Setup.exe")
        }

        (Resolve-WinUtilGitHubRelease -Repository "owner/repo").AssetName | Should -Be "Tool-Setup.exe"
    }

    It "ignores checksum and signature files published next to the build" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(
                New-GitHubTestAsset -Name "tool-x64.zip.sha256"
                New-GitHubTestAsset -Name "tool-x64.zip.sig"
                New-GitHubTestAsset -Name "tool-x64.zip"
            )
        }

        (Resolve-WinUtilGitHubRelease -Repository "owner/repo").AssetName | Should -Be "tool-x64.zip"
    }

    It "reports a release that has no installer asset" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(New-GitHubTestAsset -Name "tool.tar.gz")
        }

        { Resolve-WinUtilGitHubRelease -Repository "owner/repo" } | Should -Throw "*no installer asset*"
    }

    It "explains the rate limit and names GITHUB_TOKEN" {
        Mock Invoke-RestMethod {
            throw "Response status code does not indicate success: 403 (rate limit exceeded)."
        }

        { Resolve-WinUtilGitHubRelease -Repository "owner/repo" } | Should -Throw "*GITHUB_TOKEN*"
    }

    It "reports a repository without a published release" {
        Mock Invoke-RestMethod {
            throw "Response status code does not indicate success: 404 (Not Found)."
        }

        { Resolve-WinUtilGitHubRelease -Repository "owner/missing" } | Should -Throw "*has no published release*"
    }

    It "authenticates with GITHUB_TOKEN when one is set" {
        Mock Invoke-RestMethod {
            New-GitHubTestRelease -Assets @(New-GitHubTestAsset -Name "tool-x64.msi")
        } -ParameterFilter { $Headers.Authorization -eq "Bearer test-token" }

        $env:GITHUB_TOKEN = "test-token"
        $result = Resolve-WinUtilGitHubRelease -Repository "owner/repo"

        $result.AssetName | Should -Be "tool-x64.msi"
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Headers.Authorization -eq "Bearer test-token"
        }
    }

    It "rejects a repository that is not an owner/repo pair" {
        { Resolve-WinUtilGitHubRelease -Repository "justaname" } | Should -Throw
    }
}

Describe "Install-WinUtilProgramGitHub" {
    BeforeEach {
        $script:savedLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $TestDrive
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:savedLocalAppData
    }

    It "installs an msi silently and removes the download" {
        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.msi" }
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value "installer" -NoNewline }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Remove-Item { }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Succeeded"
        $result.Manager | Should -Be "github"
        $result.Package | Should -Be "owner/repo"
        $result.ExitCode | Should -Be 0
        $result.Detail | Should -Be "exit code 0"
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq "msiexec.exe" -and $ArgumentList -match "/qn"
        }
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -like "*WinUtilGitHub-*"
        }
    }

    It "refuses a download that does not match the published digest" {
        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.msi" -Digest ("0" * 64) }
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value "installer" -NoNewline }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Failed"
        $result.Detail | Should -BeLike "*SHA256*"
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It "accepts a download that matches the published digest" {
        $source = Join-Path $TestDrive "verified-installer"
        Set-Content -LiteralPath $source -Value "verified-installer" -NoNewline
        $digest = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash

        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.msi" -Digest $digest }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $source -Destination $OutFile }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Succeeded"
    }

    It "warns but installs when the release publishes no digest" {
        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.msi" }
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value "installer" -NoNewline }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Write-WinUtilLog { }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Succeeded"
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -like "*publishes no SHA256 digest*"
        }
    }

    It "runs an executable with the configured arguments" {
        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.exe" }
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value "installer" -NoNewline }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage -Arguments "/S")

        $result.Outcome | Should -Be "Succeeded"
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            [System.IO.Path]::GetFileName($FilePath) -ne "msiexec.exe" -and $ArgumentList -eq "/S"
        }
    }

    It "reports a failing installer exit code" {
        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.msi" }
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value "installer" -NoNewline }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 5 } }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Failed"
        $result.ExitCode | Should -Be 5
        $result.Detail | Should -BeLike "*5*"
    }

    It "treats a reboot exit code as success" {
        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.msi" }
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value "installer" -NoNewline }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 3010 } }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Succeeded"
        $result.Detail | Should -BeLike "*restart*"
    }

    It "rejects an unsupported asset type" {
        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool.tar.gz" }
        Mock Invoke-WebRequest { }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage -Type "tar")

        $result.Outcome | Should -Be "Failed"
        $result.Detail | Should -BeLike "*Unsupported*"
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It "extracts a zip into the per-user install directory and checks the binary" {
        $payload = Join-Path $TestDrive "payload"
        New-Item -ItemType Directory -Path $payload -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $payload "tool.exe") -Value "binary" -NoNewline
        $zip = Join-Path $TestDrive "tool-x64.zip"
        [System.IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip)

        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.zip" }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $zip -Destination $OutFile }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage -Bin "tool.exe")

        $result.Outcome | Should -Be "Succeeded"
        $installDir = Join-Path (Join-Path $TestDrive "winutil\github") "owner_repo"
        Test-Path -LiteralPath (Join-Path $installDir "tool.exe") | Should -BeTrue
    }

    It "fails when the archive lacks the configured binary" {
        $payload = Join-Path $TestDrive "payload-nobin"
        New-Item -ItemType Directory -Path $payload -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $payload "other.exe") -Value "binary" -NoNewline
        $zip = Join-Path $TestDrive "bundle-nobin.zip"
        [System.IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip)

        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.zip" }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $zip -Destination $OutFile }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage -Repository "owner/other" -Bin "tool.exe")

        $result.Outcome | Should -Be "Failed"
        $result.Detail | Should -BeLike "*configured binary*"
    }

    It "refuses an archive member that escapes the install directory" {
        $zip = Join-Path $TestDrive "escape.zip"
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $archive.CreateEntry("../escaped.txt")
            $writer = New-Object System.IO.StreamWriter($entry.Open())
            $writer.Write("escaped")
            $writer.Dispose()
        } finally {
            $archive.Dispose()
        }

        Mock Resolve-WinUtilGitHubRelease { New-GitHubInstallRelease -AssetName "tool-x64.zip" }
        Mock Invoke-WebRequest { Copy-Item -LiteralPath $zip -Destination $OutFile }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Failed"
        $result.Detail | Should -BeLike "*outside the install directory*"
        Test-Path -LiteralPath (Join-Path $TestDrive "winutil\github\escaped.txt") | Should -BeFalse
    }

    It "reports a resolver failure against the package" {
        Mock Resolve-WinUtilGitHubRelease { throw "GitHub repository 'owner/repo' has no published release." }

        $result = Install-WinUtilProgramGitHub -Action Install -Packages @(New-GitHubInstallPackage)

        $result.Outcome | Should -Be "Failed"
        $result.Package | Should -Be "owner/repo"
        $result.Detail | Should -BeLike "*has no published release*"
    }

    It "skips a package without a repository" {
        $results = @(Install-WinUtilProgramGitHub -Action Install -Packages @([pscustomobject]@{ github = "" }))

        $results.Count | Should -Be 0
    }
}
