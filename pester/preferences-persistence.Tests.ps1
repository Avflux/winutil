BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Save-WinUtilPreferences.ps1")
    . (Join-Path $script:repoRoot "functions\private\Read-WinUtilPreferences.ps1")
}

Describe "Save-WinUtilPreferences" {
    BeforeEach {
        $global:sync = @{
            winutildir = $TestDrive
            preferences = @{
                language = "pt-BR"
                theme = "Dark"
                packagemanager = "Winget"
            }
        }
    }

    It "creates preferences.json in winutildir" {
        Save-WinUtilPreferences
        Test-Path (Join-Path $TestDrive "preferences.json") | Should -BeTrue
    }

    It "writes valid JSON with saved values" {
        Save-WinUtilPreferences
        $raw = Get-Content (Join-Path $TestDrive "preferences.json") -Raw
        { $raw | ConvertFrom-Json } | Should -Not -Throw
        $data = $raw | ConvertFrom-Json
        $data.language | Should -Be "pt-BR"
        $data.theme | Should -Be "Dark"
        $data.packagemanager | Should -Be "Winget"
    }

    It "does not crash when winutildir is missing" {
        $global:sync.winutildir = (Join-Path $TestDrive "nonexistent")
        { Save-WinUtilPreferences } | Should -Not -Throw
    }
}

Describe "Read-WinUtilPreferences" {
    BeforeEach {
        $global:sync = @{
            winutildir = $TestDrive
            preferences = @{
                language = "en-US"
                theme = "Auto"
                packagemanager = "Winget"
            }
        }
    }

    It "restores saved preferences from file" {
        @{
            language = "pt-BR"
            theme = "Dark"
            packagemanager = "Choco"
        } | ConvertTo-Json | Set-Content (Join-Path $TestDrive "preferences.json")

        Read-WinUtilPreferences
        $global:sync.preferences.language | Should -Be "pt-BR"
        $global:sync.preferences.theme | Should -Be "Dark"
        $global:sync.preferences.packagemanager | Should -Be "Choco"
    }

    It "keeps defaults when file is missing" {
        $prefsFile = Join-Path $TestDrive "preferences.json"
        if (Test-Path $prefsFile) { Remove-Item $prefsFile -Force }
        Read-WinUtilPreferences
        $global:sync.preferences.language | Should -Be "en-US"
        $global:sync.preferences.theme | Should -Be "Auto"
    }

    It "keeps defaults when file is corrupted" {
        "NOT JSON" | Set-Content (Join-Path $TestDrive "preferences.json")
        Read-WinUtilPreferences
        $global:sync.preferences.language | Should -Be "en-US"
    }

    It "does not crash when winutildir is missing" {
        $global:sync.winutildir = (Join-Path $TestDrive "nonexistent")
        { Read-WinUtilPreferences } | Should -Not -Throw
    }
}

Describe "Language round-trip" {
    It "saves and restores language preference" {
        $global:sync = @{
            winutildir = $TestDrive
            preferences = @{
                language = "en-US"
                theme = "Auto"
                packagemanager = "Winget"
            }
        }

        # Simulate changing language
        $global:sync.preferences.language = "pt-BR"
        Save-WinUtilPreferences

        # Simulate restart
        $global:sync.preferences.language = "en-US"
        Read-WinUtilPreferences

        $global:sync.preferences.language | Should -Be "pt-BR"
    }
}
