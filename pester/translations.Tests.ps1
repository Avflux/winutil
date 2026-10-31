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

    It "covers interface and accessibility strings found without a Portuguese translation" {
        $json = Get-Content -Path $script:translationsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $pt = $json.'pt-BR'
        $keys = @(
            'Cut',
            'Copy',
            'Paste',
            (([char]0x26A0) + ' Offline Mode - No Internet Connection'),
            'Install and upgrade applications',
            'Apply Windows tweaks',
            'Import and export configurations',
            'Manage Windows Update profiles',
            'Create a customized Windows 11 ISO or USB',
            '- Notifies when downloaded updates are ready to install',
            ' Select Installed ',
            ' Select Installed Tweaks ',
            'Injects boot-storage drivers for Setup and adds exported drivers to the selected install.wim edition individually, skipping incompatible packages.',
            'Working...',
            'This can take several minutes. Progress is written to the status log.',
            'Install tab',
            'Tweaks tab',
            'Config tab',
            'Updates tab',
            'Win11 Creator tab',
            'Search',
            'Clear Search',
            'Theme',
            'Previous Step',
            'Next Step',
            'Progress',
            'Free and Open Source Software',
            "This will uninstall the following applications:`n{0}",
            'No modified ISO content found. Please run the modification step first.',
            'AB Download Manager is an open-source download accelerator and manager with multi-threaded downloads, queue scheduling, speed limiting, and browser integration.',
            'DBeaver Community is a free, open-source universal database tool for developers, SQL programmers, database administrators, and analysts.',
            'Krita is a free and open-source painting tool designed for concept artists, illustrators, matte and texture artists, and the VFX industry.',
            'ImHex is a free and open-source hex editor for reverse engineers and programmers, featuring a custom pattern language for decoding binary formats, a disassembler, and data analysis tools.',
            'Kiro is an agentic IDE from AWS that turns prompts into specs, then into working code, docs, and tests through spec-driven development workflows.',
            'RStudio is an integrated development environment (IDE) for R, with a console, syntax-highlighting editor, and tools for plotting, history, debugging, and workspace management.',
            'opencode is an AI coding agent built for the terminal, with a native TUI, automatic LSP loading, parallel agents, and support for 75+ LLM providers including local models.',
            'Microsoft Sysinternals PsTools provides utilities for managing local and remote Windows systems and monitoring processes. PsExec can run processes under the SYSTEM account when the user has local administrative rights on the target system.',
            'SyncTrayzor is a Windows tray utility that bundles and wraps Syncthing, making it behave like a native application to easily manage and monitor file synchronization.',
            'Syncthing is a decentralized, peer-to-peer file synchronization tool that securely syncs files directly across devices without cloud servers, managed via a local web interface.',
            'CurseForge is a desktop application for managing mods and modpacks across multiple games, powered by Overwolf.',
            'Sets some services to Manual startup.',
            'svchost.exe Splitting - Disable',
            'Disables service-host splitting to reduce the number of svchost.exe processes and modestly lower memory overhead. Recommended for low-performance systems with 12 GB of RAM or less. Can interfere with Xbox services. Restart Windows after changing this setting.',
            'Downloads O&O ShutUp10++ (about 82 MB) from oo-software.com on every click and launches it. Nothing is installed; the file is saved under %LocalAppData%\winutil.',
            'Fast Startup - Disable',
            'Disables Windows Fast Startup (hybrid shutdown). This helps dual-boot setups and avoids stale hardware state between sessions.',
            'File Explorer Sync Provider Notifications - Disable',
            'Stops File Explorer from displaying sync-provider notifications and promotional suggestions, such as OneDrive or Office ads.',
            'Virtual Machine Platform - Enable',
            'Enables the Virtual Machine Platform, a required component for WSL 2 and other virtualization-based workloads.',
            'Telnet Client - Enable',
            'Enables the Telnet client command-line tool for connecting to remote hosts over the Telnet protocol.',
            'TFTP Client - Enable',
            'Enables the Trivial File Transfer Protocol (TFTP) client for transferring files to and from remote hosts.',
            'Synchronizes text messages, phone notifications, photos, and calls from a mobile device to the desktop.'
        )
        foreach ($key in $keys) {
            $pt.PSObject.Properties[$key].Value | Should -Not -BeNullOrEmpty -Because "The translation for '$key' should be present."
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
        . (Join-Path $script:repoRoot "functions\Core\Get-WinUtilText.ps1")
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
        . (Join-Path $script:repoRoot "functions\Core\Get-WinUtilText.ps1")
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

    It "formats the configured counter label when the translation template is missing" {
        $global:sync = @{
            preferences = @{ language = "en-US" }
            configs = @{
                translations = @{ "en-US" = [pscustomobject]@{} }
                appnavigation = @{ WPFselectedAppsButton = [pscustomobject]@{ Content = "Selected Apps: 0" } }
            }
        }
        Get-WinUtilSelectedAppsCountText -Count 7 | Should -Be "Selected Apps: 7"
    }

    It "falls back to the default template when no config is loaded" {
        $global:sync = @{ preferences = @{ language = "en-US" }; configs = @{} }
        Get-WinUtilSelectedAppsCountText -Count 2 | Should -Be "Selected Apps: 2"
    }
}

Describe "Get-WinUtilTranslatedToolTip and Get-WinUtilTranslatedDescription" {
    BeforeAll {
        . (Join-Path $script:repoRoot "functions\Core\Get-WinUtilText.ps1")
        . (Join-Path $script:repoRoot "functions\UI\Get-WinUtilEntryToolTip.ps1")
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
        . (Join-Path $script:repoRoot "functions\Core\Write-WinUtilLog.ps1")
        . (Join-Path $script:repoRoot "functions\Core\Get-WinUtilText.ps1")
        . (Join-Path $script:repoRoot "functions\UI\Get-WinUtilEntryToolTip.ps1")
        . (Join-Path $script:repoRoot "functions\UI\Invoke-WinUtilTranslation.ps1")
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

    It "translates and restores an AutomationProperties.Name label" {
        $btn = New-Object Windows.Controls.Button
        [System.Windows.Automation.AutomationProperties]::SetName($btn, "Install tab")
        $ptTable = [pscustomobject]@{ "Install tab" = "Aba Instalar" }

        $global:sync = @{
            Form = New-Object Windows.Window
            preferences = @{ language = "en-US" }
            configs = @{ translations = @{ "pt-BR" = $ptTable; "en-US" = [pscustomobject]@{} } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $global:sync.Form.Content = $btn

        Invoke-WinUtilTranslation -Language "pt-BR"
        [System.Windows.Automation.AutomationProperties]::GetName($btn) | Should -Be "Aba Instalar"

        Invoke-WinUtilTranslation -Language "en-US"
        [System.Windows.Automation.AutomationProperties]::GetName($btn) | Should -Be "Install tab"
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

    It "translates application hover tooltips in visual/items tree" {
        $border = New-Object Windows.Controls.Border
        $border.ToolTip = "Betterbird is a fork of Mozilla Thunderbird with additional features and bugfixes.`n`nPreset key: WPFInstallbetterbird"
        $ptTable = [pscustomobject]@{
            "Betterbird is a fork of Mozilla Thunderbird with additional features and bugfixes." = "Betterbird $([char]0x00E9) um fork do Mozilla Thunderbird com recursos adicionais e corre$([char]0x00E7)$([char]0x00F5)es de bugs."
        }

        $global:sync = @{
            Form = New-Object Windows.Window
            preferences = @{ language = "en-US" }
            configs = @{ translations = @{ "pt-BR" = $ptTable; "en-US" = [pscustomobject]@{} } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $global:sync.Form.Content = $border

        Invoke-WinUtilTranslation -Language "pt-BR"
        $border.ToolTip | Should -Be "Betterbird $([char]0x00E9) um fork do Mozilla Thunderbird com recursos adicionais e corre$([char]0x00E7)$([char]0x00F5)es de bugs.`n`nPreset key: WPFInstallbetterbird"

        Invoke-WinUtilTranslation -Language "en-US"
        $border.ToolTip | Should -Be "Betterbird is a fork of Mozilla Thunderbird with additional features and bugfixes.`n`nPreset key: WPFInstallbetterbird"
    }

    It "translates category toggle buttons with prefix" {
        $lbl = New-Object Windows.Controls.Label
        $lbl.Tag = "CategoryToggleButton"
        $lbl.Content = "- Communications"
        $ptTable = [pscustomobject]@{
            "Communications" = "Comunica$([char]0x00E7)$([char]0x00E3)o"
        }

        $global:sync = @{
            Form = New-Object Windows.Window
            preferences = @{ language = "en-US" }
            configs = @{ translations = @{ "pt-BR" = $ptTable; "en-US" = [pscustomobject]@{} } }
            TextBaselines = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
        }
        $global:sync.Form.Content = $lbl

        Invoke-WinUtilTranslation -Language "pt-BR"
        $lbl.Content | Should -Be "- Comunica$([char]0x00E7)$([char]0x00E3)o"

        Invoke-WinUtilTranslation -Language "en-US"
        $lbl.Content | Should -Be "- Communications"
    }
}
