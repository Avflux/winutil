BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:translationsPath = Join-Path $script:repoRoot "config\translations.json"
}

Describe "Translation config" {
    It "parses as valid JSON" {
        { Get-Content -Path $script:translationsPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "has an en-US language entry" {
        $json = Get-Content -Path $script:translationsPath -Raw | ConvertFrom-Json
        $null -ne $json.'en-US' | Should -BeTrue
    }

    It "has a pt-BR language entry with all values non-empty" {
        $json = Get-Content -Path $script:translationsPath -Raw | ConvertFrom-Json
        $pt = $json.'pt-BR'
        $pt | Should -Not -BeNullOrEmpty
        $empty = @($pt.PSObject.Properties | Where-Object {
            [string]::IsNullOrWhiteSpace($_.Value) -and $_.Name -notmatch '^---.*---$'
        })
        $empty | Should -BeNullOrEmpty
    }

    It "does not contain duplicate keys in pt-BR" {
        $raw = Get-Content -Path $script:translationsPath -Raw
        $matches = [regex]::Matches($raw, '(?m)^\s{8}"(.+?)"\s*:')
        $uniqueKeys = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $matches.Count | Should -Be $uniqueKeys.Count
    }

    It "covers the counter template key" {
        $json = Get-Content -Path $script:translationsPath -Raw | ConvertFrom-Json
        $json.'pt-BR'.'Selected Apps: {0}' | Should -Not -BeNullOrEmpty
    }

    It "covers the menu and button labels visible in the title bar" {
        $json = Get-Content -Path $script:translationsPath -Raw | ConvertFrom-Json
        $pt = $json.'pt-BR'
        @('Auto', 'Dark', 'Light', 'Language', 'Settings', 'Minimize', 'Maximize', 'Restore', 'Close') | ForEach-Object {
            $pt.PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WinUtilTranslation" {
    BeforeAll {
        . (Join-Path $script:repoRoot "functions\private\Get-WinUtilText.ps1")
    }

    It "returns the input when no translation table is loaded" {
        $global:sync = @{ preferences = @{ language = "pt-BR" }; configs = @{ translations = $null } }
        Get-WinUtilTranslation -Text "Settings" | Should -Be "Settings"
    }

    It "returns the input when the language is en-US" {
        $global:sync = @{ preferences = @{ language = "en-US" }; configs = @{ translations = @{ "pt-BR" = [pscustomobject]@{ "Settings" = "Configuracoes" } } } }
        Get-WinUtilTranslation -Text "Settings" | Should -Be "Settings"
    }

    It "translates a known key" {
        $global:sync = @{ preferences = @{ language = "pt-BR" }; configs = @{ translations = @{ "pt-BR" = [pscustomobject]@{ "Settings" = [char]0x00C7 + "onfigura" + [char]0x00E7 + [char]0x00F5 + "es" } } } }
        Get-WinUtilTranslation -Text "Settings" | Should -Be ([char]0x00C7 + "onfigura" + [char]0x00E7 + [char]0x00F5 + "es")
    }

    It "falls back to English for an unknown key" {
        $global:sync = @{ preferences = @{ language = "pt-BR" }; configs = @{ translations = @{ "pt-BR" = [pscustomobject]@{} } } }
        Get-WinUtilTranslation -Text "SomeUnknownString" | Should -Be "SomeUnknownString"
    }

    It "handles null and empty input" {
        $global:sync = @{ preferences = @{ language = "pt-BR" }; configs = @{ translations = @{} } }
        Get-WinUtilTranslation -Text $null | Should -BeNullOrEmpty
        Get-WinUtilTranslation -Text "" | Should -BeNullOrEmpty
    }
}

Describe "Get-WinUtilSelectedAppsCountText" {
    BeforeAll {
        . (Join-Path $script:repoRoot "functions\private\Get-WinUtilText.ps1")
    }

    It "formats the counter with the translated template" {
        $ptTemplate = [pscustomobject]@{ "Selected Apps: {0}" = "Aplicativos Selecionados: {0}" }
        $global:sync = @{
            preferences = @{ language = "pt-BR" }
            configs = @{
                translations = @{ "pt-BR" = $ptTemplate }
                appnavigation = @{ WPFselectedAppsButton = [pscustomobject]@{ Content = "Selected Apps: 0" } }
            }
        }
        Get-WinUtilSelectedAppsCountText -Count 3 | Should -Be "Aplicativos Selecionados: 3"
    }

    It "falls back to English when the template is missing" {
        $global:sync = @{
            preferences = @{ language = "pt-BR" }
            configs = @{
                translations = @{ "pt-BR" = [pscustomobject]@{} }
                appnavigation = @{ WPFselectedAppsButton = [pscustomobject]@{ Content = "Selected Apps: 0" } }
            }
        }
        Get-WinUtilSelectedAppsCountText -Count 7 | Should -Be "Selected Apps: 0"
    }

    It "falls back to the default template when no config is loaded" {
        $global:sync = @{ preferences = @{ language = "en-US" }; configs = @{} }
        Get-WinUtilSelectedAppsCountText -Count 2 | Should -Be "Selected Apps: 2"
    }
}
