function Get-WinUtilTranslation {

    <#

    .SYNOPSIS
        Resolves the translated text for an English UI string.

    .DESCRIPTION
        Looks the string up in the language selected through $sync.preferences.language.
        English is the source language: the lookup returns the input unchanged, so callers
        do not need to special-case it. A language without a translation table, or a string
        the selected language does not cover, also falls back to the English input.

    .PARAMETER Text
        The English source string to translate.

    .OUTPUTS
        System.String - the translated text, or the input when no translation applies.

    #>

    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $language = $sync.preferences.language
    if (-not $language -or $language -eq "en-US") {
        return $Text
    }

    $table = $sync.configs.translations.$language
    if (-not $table) {
        return $Text
    }

    $translated = $table.PSObject.Properties[$Text].Value
    if ([string]::IsNullOrEmpty($translated)) {
        return $Text
    }
    return $translated
}

function Get-WinUtilTextBaseline {

    <#

    .SYNOPSIS
        Returns the English string recorded for a control property.

    .DESCRIPTION
        Translated controls need their original text back when the interface returns to
        English, and config-rendered toggles carry live state in their Tag, so the baseline
        lives in a side table keyed by the control instance instead. Entries are recorded the
        first time a control is seen and survive for the life of the control, which makes
        apply and restore idempotent.

    .PARAMETER Control
        The translated control, or an individual text Run.

    .PARAMETER Kind
        Which property the baseline is for: "Content", "Text", "ToolTip", or "Header".

    .PARAMETER Current
        The value to record when no baseline exists yet.

    .OUTPUTS
        System.String - the recorded English string, or an empty string when the property was
        never translated.

    #>

    param($Control, [string]$Kind, $Current)

    if (-not $sync.TextBaselines) {
        return [string]$Current
    }
    $baselines = $sync.TextBaselines
    $entry = $baselines.GetValue($Control)
    if (-not $entry) {
        $entry = @{}
        $baselines.Add($Control, $entry)
    }
    if (-not $entry.ContainsKey($Kind)) {
        $entry[$Kind] = [string]$Current
    }
    return $entry[$Kind]
}

function Set-WinUtilTextBaseline {

    <#

    .SYNOPSIS
        Records the English string for a control property.

    .DESCRIPTION
        Controls whose text is produced at render time, such as the selected-apps popup
        entries, are born already translated. They record their English source here so the
        walker's first sight of them does not mistake the translated text for the baseline.

    .PARAMETER Control
        The translated control, or an individual text Run.

    .PARAMETER Kind
        Which property the baseline is for: "Content", "Text", "ToolTip", or "Header".

    .PARAMETER English
        The English string to record.

    #>

    param($Control, [string]$Kind, [string]$English)

    if (-not $sync.TextBaselines) { return }
    $baselines = $sync.TextBaselines
    $entry = $baselines.GetValue($Control)
    if (-not $entry) {
        $entry = @{}
        $baselines.Add($Control, $entry)
    }
    $entry[$Kind] = $English
}

function Set-WinUtilTranslatedText {

    <#

    .SYNOPSIS
        Sets a control property to the selected language and records its English source.

    .DESCRIPTION
        One call for render-time translation: the English string goes into the baseline side
        table and the property receives the translation, so a later walk can restore the
        original when the interface goes back to English.

    .PARAMETER Control
        The control to translate.

    .PARAMETER Kind
        Which property to set: "Content", "Text", "ToolTip", or "Header".

    .PARAMETER English
        The English source string the property is showing.

    #>

    param($Control, [ValidateSet("Content", "Text", "ToolTip", "Header")][string]$Kind, [string]$English)

    Set-WinUtilTextBaseline -Control $Control -Kind $Kind -English $English
    $translated = Get-WinUtilTranslation -Text $English
    switch ($Kind) {
        "Content" { $Control.Content = $translated }
        "Text"    { $Control.Text = $translated }
        "ToolTip" { $Control.ToolTip = $translated }
        "Header"  { $Control.Header = $translated }
    }
}

function Get-WinUtilSelectedAppsCountText {

    <#

    .SYNOPSIS
        Builds the "Selected Apps: N" counter text in the selected language.

    .DESCRIPTION
        The counter is rebuilt from a number by several callers. It uses the translated
        "Selected Apps: {0}" template when the selected language provides one and falls back
        to the label from the app navigation config, so the format lives in one place instead
        of being re-derived at every call site.

    .PARAMETER Count
        The number of currently selected applications.

    .OUTPUTS
        System.String - the counter text ready for display.

    #>

    param([int]$Count)

    $template = $null
    if ($sync.configs.translations -and $sync.preferences.language) {
        $table = $sync.configs.translations.($sync.preferences.language)
        if ($table) {
            $template = $table.PSObject.Properties["Selected Apps: {0}"].Value
        }
    }
    if ([string]::IsNullOrWhiteSpace($template)) {
        $template = $sync.configs.appnavigation.WPFselectedAppsButton.Content
    }
    if ([string]::IsNullOrWhiteSpace($template)) {
        $template = "Selected Apps: {0}"
    }
    return $template -f $Count
}

function Get-WinUtilTranslatedToolTip {

    <#

    .SYNOPSIS
        Translates an entry description and appends the preset key for use as a tooltip.

    .DESCRIPTION
        Translates the description via the active language table, records the English
        baseline so the tree walker can restore it on language switches, and appends
        the preset key suffix. When the description is null or whitespace, returns
        only the key line.

    .PARAMETER Description
        The entry's English description from the config JSON.

    .PARAMETER Key
        The entry's JSON key as used in preset files.

    #>

    param(
        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $translated = Get-WinUtilTranslation -Text $Description
    return Get-WinUtilEntryToolTip -Description $translated -Key $Key
}

function Get-WinUtilTranslatedDescription {

    <#

    .SYNOPSIS
        Translates a description string for use as a tooltip.

    .DESCRIPTION
        Translates the description via the active language table. Used for tooltips
        that only show the description without a preset key suffix (toggles,
        combobox labels, radio buttons).

    .PARAMETER Description
        The entry's English description from the config JSON.

    #>

    param(
        [Parameter(Mandatory = $false)]
        [string]$Description
    )

    return Get-WinUtilTranslation -Text $Description
}
