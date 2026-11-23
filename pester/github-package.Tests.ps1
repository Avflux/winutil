#===========================================================================
# Tests - GitHub release source
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    . (Join-Path $script:repoRoot "functions\Apps\Resolve-WinUtilGitHubRelease.ps1")

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
