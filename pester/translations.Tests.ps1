BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:translationsPath = Join-Path $script:repoRoot "config\translations.json"
}

Describe "Translation config" {
    It "parses as valid JSON" {
        { Get-Content -Path $script:translationsPath -Raw -Encoding utf8 | ConvertFrom-Json } | Should -Not -Throw
    }

    It "has an en-US language entry" {
        $json = Get-Content -Path $script:translationsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $null -ne $json.'en-US' | Should -BeTrue
    }

    It "has a pt-BR language entry with all values non-empty" {
        $json = Get-Content -Path $script:translationsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $pt = $json.'pt-BR'
        $pt | Should -Not -BeNullOrEmpty
        $empty = @($pt.PSObject.Properties | Where-Object {
            [string]::IsNullOrWhiteSpace($_.Value) -and $_.Name -notmatch '^---.*---$'
        })
        $empty | Should -BeNullOrEmpty
    }

    It "does not contain duplicate keys in pt-BR" {
        $raw = Get-Content -Path $script:translationsPath -Raw -Encoding utf8
        $matches = [regex]::Matches($raw, '(?m)^\s{8}"(.+?)"\s*:')
        $uniqueKeys = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $matches.Count | Should -Be $uniqueKeys.Count
    }

    It "covers the counter template key" {
        $json = Get-Content -Path $script:translationsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $json.'pt-BR'.'Selected Apps: {0}' | Should -Not -BeNullOrEmpty
    }

    It "covers the menu and button labels visible in the title bar" {
        $json = Get-Content -Path $script:translationsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $pt = $json.'pt-BR'
        @('Auto', 'Dark', 'Light', 'Language', 'Settings', 'Minimize', 'Maximize', 'Restore', 'Close') | ForEach-Object {
            $pt.PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }
    }

    It "preserves Portuguese accented characters without ANSI double encoding" {
        $json = Get-Content -Path $script:translationsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $pt = $json.'pt-BR'
        $pt.PSObject.Properties['Standard'].Value | Should -Be ("Padr" + [char]0x00E3 + "o")
        $pt.PSObject.Properties['Recommended Selections:'].Value | Should -Be ("Sele" + [char]0x00E7 + [char]0x00F5 + "es Recomendadas:")
        $pt.PSObject.Properties['Minimal'].Value | Should -Be ("M" + [char]0x00ED + "nimo")
        $pt.PSObject.Properties['Advanced'].Value | Should -Be ("Avan" + [char]0x00E7 + "ado")
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

Describe "Get-WinUtilTranslatedToolTip and Get-WinUtilTranslatedDescription" {
    BeforeAll {
        . (Join-Path $script:repoRoot "functions\private\Get-WinUtilText.ps1")
        . (Join-Path $script:repoRoot "functions\private\Get-WinUtilEntryToolTip.ps1")
    }

    It "translates description and appends preset key" {
        $ptTable = [pscustomobject]@{ "Fast browser" = "Navegador rapido" }
        $global:sync = @{
            preferences = @{ language = "pt-BR" }
            configs = @{ translations = @{ "pt-BR" = $ptTable } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $dummy = [pscustomobject]@{ ToolTip = "" }
        $tip = Get-WinUtilTranslatedToolTip -Description "Fast browser" -Key "WPFInstallBrave" -Control $dummy
        $tip | Should -Be "Navegador rapido`n`nPreset key: WPFInstallBrave"
        Get-WinUtilTextBaseline -Control $dummy -Kind "ToolTip" -Current "" | Should -Be "Fast browser"
    }

    It "translates plain description and records baseline" {
        $ptTable = [pscustomobject]@{ "Dark mode setting" = "Configuracao de modo escuro" }
        $global:sync = @{
            preferences = @{ language = "pt-BR" }
            configs = @{ translations = @{ "pt-BR" = $ptTable } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $dummy = [pscustomobject]@{ ToolTip = "" }
        $desc = Get-WinUtilTranslatedDescription -Description "Dark mode setting" -Control $dummy
        $desc | Should -Be "Configuracao de modo escuro"
        Get-WinUtilTextBaseline -Control $dummy -Kind "ToolTip" -Current "" | Should -Be "Dark mode setting"
    }

    It "recovers English baseline via reverse lookup when created under non-English language without prior baseline" {
        $ptTable = [pscustomobject]@{ "Essential Tweaks" = "Ajustes Essenciais" }
        $global:sync = @{
            preferences = @{ language = "pt-BR" }
            configs = @{ translations = @{ "pt-BR" = $ptTable } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $dummy = [pscustomobject]@{ ToolTip = "" }
        # Suppose $dummy has Portuguese text already and was not registered with -Control
        $baseline = Get-WinUtilTextBaseline -Control $dummy -Kind "ToolTip" -Current "Ajustes Essenciais"
        $baseline | Should -Be "Essential Tweaks"
    }
}

Describe "Invoke-WinUtilTranslation ToolTip handling" {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        . (Join-Path $script:repoRoot "functions\private\Write-WinUtilLog.ps1")
        . (Join-Path $script:repoRoot "functions\private\Get-WinUtilText.ps1")
        . (Join-Path $script:repoRoot "functions\private\Get-WinUtilEntryToolTip.ps1")
        . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilTranslation.ps1")
    }

    It "translates tooltip with preset key suffix and restores it on language change" {
        $ptTable = [pscustomobject]@{
            "Essential Tweaks" = "Ajustes Essenciais"
        }
        $cb = New-Object Windows.Controls.CheckBox
        $cb.ToolTip = "Essential Tweaks`n`nPreset key: WPFTweaksTele"

        $global:sync = @{
            Form = New-Object Windows.Window
            preferences = @{ language = "en-US" }
            configs = @{ translations = @{ "pt-BR" = $ptTable; "en-US" = [pscustomobject]@{} } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $global:sync.Form.Content = $cb

        # Translate to pt-BR
        Invoke-WinUtilTranslation -Language "pt-BR"
        $cb.ToolTip | Should -Be "Ajustes Essenciais`n`nPreset key: WPFTweaksTele"

        # Revert to en-US
        Invoke-WinUtilTranslation -Language "en-US"
        $cb.ToolTip | Should -Be "Essential Tweaks`n`nPreset key: WPFTweaksTele"
    }

    It "translates plain string tooltip and restores it" {
        $ptTable = [pscustomobject]@{
            "Clear Selection" = "Limpar Selecao"
        }
        $btn = New-Object Windows.Controls.Button
        $btn.ToolTip = "Clear Selection"

        $global:sync = @{
            Form = New-Object Windows.Window
            preferences = @{ language = "en-US" }
            configs = @{ translations = @{ "pt-BR" = $ptTable; "en-US" = [pscustomobject]@{} } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $global:sync.Form.Content = $btn

        Invoke-WinUtilTranslation -Language "pt-BR"
        $btn.ToolTip | Should -Be "Limpar Selecao"

        Invoke-WinUtilTranslation -Language "en-US"
        $btn.ToolTip | Should -Be "Clear Selection"
    }

    It "leaves key-only tooltips unchanged" {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.ToolTip = "Preset key: WPFTweaksTele"

        $global:sync = @{
            Form = New-Object Windows.Window
            preferences = @{ language = "en-US" }
            configs = @{ translations = @{ "pt-BR" = [pscustomobject]@{}; "en-US" = [pscustomobject]@{} } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $global:sync.Form.Content = $cb

        Invoke-WinUtilTranslation -Language "pt-BR"
        $cb.ToolTip | Should -Be "Preset key: WPFTweaksTele"
    }
}

