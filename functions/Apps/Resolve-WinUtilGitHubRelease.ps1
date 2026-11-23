function Resolve-WinUtilGitHubRelease {
    <#

    .SYNOPSIS
        Resolves the release asset that installs an application published on GitHub.

    .DESCRIPTION
        Applications that ship only a GitHub release have no package manager manifest to read,
        so the release itself is the manifest: ask the API for the latest release, choose the
        asset the config points at or the one that matches the architecture, and return the
        download URL together with the published SHA256 when the release provides one.

        The release payload is cached per repository for the life of the run. Several apps from
        the same project then cost a single request, which matters because anonymous GitHub API
        access allows 60 requests per hour. Assign a new hashtable to
        $script:WinUtilGitHubReleaseCache to start cold; the tests do that between cases.

    .PARAMETER Repository
        The "owner/repo" pair taken from the application config.

    .PARAMETER AssetPattern
        Optional regular expression matched against asset names. The config carries it because
        projects name their assets differently. A pattern that matches nothing fails with the
        list of published assets so it can be corrected.

    .PARAMETER Architecture
        The architecture to install for, x64 by default. Used to choose between assets when no
        pattern is given; a release that only publishes another architecture's build is rejected
        rather than installed.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Repository, Version, AssetName,
        DownloadUrl, Digest and Size.

    #>

    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
        [string]$Repository,

        [string]$AssetPattern,

        [ValidateSet("x64", "arm64", "x86")]
        [string]$Architecture = "x64"
    )

    if ($null -eq $script:WinUtilGitHubReleaseCache) {
        $script:WinUtilGitHubReleaseCache = @{}
    }

    $cacheKey = $Repository.ToLowerInvariant()

    if ($script:WinUtilGitHubReleaseCache.ContainsKey($cacheKey)) {
        $release = $script:WinUtilGitHubReleaseCache[$cacheKey]
    } else {
        $headers = @{
            "Accept"     = "application/vnd.github+json"
            "User-Agent" = "WinUtil"
        }
        if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
            $headers["Authorization"] = "Bearer $($env:GITHUB_TOKEN)"
        }

        try {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers $headers -TimeoutSec 30
        } catch {
            $message = $_.Exception.Message
            $statusCode = $null
            if ($_.Exception.PSObject.Properties["Response"] -and $_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            } elseif ($message -match '\b([45]\d\d)\b') {
                # A wrapped or mocked failure carries the code in the text, not in a response
                $statusCode = [int]$Matches[1]
            }

            if ($statusCode -eq 404) {
                throw "GitHub repository '$Repository' has no published release."
            }
            if ($statusCode -eq 403 -or $statusCode -eq 429) {
                throw "GitHub API rate limit reached while resolving '$Repository'. Set the GITHUB_TOKEN environment variable to raise the limit."
            }
            throw "Could not read the latest release for '$Repository': $message"
        }

        $script:WinUtilGitHubReleaseCache[$cacheKey] = $release
    }

    $assets = @($release.assets | Where-Object { $_.name -and $_.browser_download_url })
    if ($assets.Count -eq 0) {
        throw "The latest release of '$Repository' ($($release.tag_name)) publishes no downloadable asset."
    }

    if (-not [string]::IsNullOrWhiteSpace($AssetPattern)) {
        $matched = @($assets | Where-Object { $_.name -match $AssetPattern })
        if ($matched.Count -eq 0) {
            $available = (@($assets | ForEach-Object { $_.name }) | Sort-Object) -join ", "
            throw "No asset in the latest release of '$Repository' matches '$AssetPattern'. Available assets: $available"
        }
        $asset = $matched | Sort-Object -Property name | Select-Object -First 1
    } else {
        $asset = Select-WinUtilGitHubAsset -Assets $assets -Architecture $Architecture -Repository $Repository
    }

    $digest = [string]$asset.digest
    if ($digest.StartsWith("sha256:", [System.StringComparison]::OrdinalIgnoreCase)) {
        $digest = $digest.Substring("sha256:".Length)
    }
    if ([string]::IsNullOrWhiteSpace($digest)) {
        $digest = $null
    } else {
        $digest = $digest.ToLowerInvariant()
    }

    Write-WinUtilLog -Component "Package" -Message "Resolved GitHub release ${Repository} $($release.tag_name): $($asset.name)"

    [pscustomobject]@{
        Repository  = $Repository
        Version     = [string]$release.tag_name
        AssetName   = [string]$asset.name
        DownloadUrl = [string]$asset.browser_download_url
        Digest      = $digest
        Size        = $asset.size
    }
}

function Select-WinUtilGitHubAsset {
    <#

    .SYNOPSIS
        Chooses the release asset to install when the config gives no pattern.

    .DESCRIPTION
        Only installer formats are candidates, so checksum and signature files published
        alongside a build are never selected. Preference is msi, then exe, then zip, among
        assets that match the target architecture; a release whose asset names carry no
        architecture at all is accepted as-is. Assets built for another architecture are never
        a fallback, because installing one would produce a binary the machine cannot run.

    .PARAMETER Assets
        The release assets reported by the GitHub API.

    .PARAMETER Architecture
        The architecture to install for.

    .PARAMETER Repository
        Used to name the repository in error messages.

    .OUTPUTS
        System.Management.Automation.PSCustomObject - the selected asset.

    #>

    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Assets,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "arm64", "x86")]
        [string]$Architecture,

        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $extensionOrder = @{ ".msi" = 0; ".exe" = 1; ".zip" = 2 }
    $installable = @($Assets | Where-Object {
        $extensionOrder.ContainsKey([System.IO.Path]::GetExtension([string]$_.name).ToLowerInvariant())
    })

    if ($installable.Count -eq 0) {
        $available = (@($Assets | ForEach-Object { $_.name }) | Sort-Object) -join ", "
        throw "The latest release of '$Repository' publishes no installer asset (.msi, .exe or .zip). Available assets: $available"
    }

    $architecturePatterns = @{
        x64   = '(?i)(x64|amd64|x86_64|x86-64)'
        arm64 = '(?i)(arm64|aarch64)'
        x86   = '(?i)(x86(?!_64)|i386|win32)'
    }

    # 0 = built for the target, 1 = built for another architecture, 2 = name carries no
    # architecture at all
    $ranked = foreach ($candidate in $installable) {
        $name = [string]$candidate.name
        $rank = 2
        if ($name -match $architecturePatterns[$Architecture]) {
            $rank = 0
        } else {
            foreach ($other in @($architecturePatterns.Keys | Where-Object { $_ -ne $Architecture })) {
                if ($name -match $architecturePatterns[$other]) { $rank = 1; break }
            }
        }
        [pscustomobject]@{ Asset = $candidate; Rank = $rank }
    }

    $bestRank = ($ranked | Measure-Object -Property Rank -Minimum).Minimum
    if ($bestRank -eq 1) {
        $available = (@($installable | ForEach-Object { $_.name }) | Sort-Object) -join ", "
        throw "The latest release of '$Repository' only publishes assets for another architecture. Available assets: $available"
    }

    $ranked |
        Where-Object { $_.Rank -eq $bestRank } |
        Sort-Object -Property @(
            @{ Expression = { $extensionOrder[[System.IO.Path]::GetExtension([string]$_.Asset.name).ToLowerInvariant()] } }
            @{ Expression = { [string]$_.Asset.name } }
        ) |
        Select-Object -First 1 -ExpandProperty Asset
}
