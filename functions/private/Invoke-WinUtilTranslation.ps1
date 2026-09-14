function Invoke-WinUtilTranslation {

    <#

    .SYNOPSIS
        Applies or reverts the interface translation of the WinUtil window.

    .DESCRIPTION
        Walks the visual and logical tree of the window and the title-bar popups, swapping
        the static English labels for the selected language and recording every replaced
        string in a baseline side table, so switching back to English restores the original
        text even where a translation is missing.

        Scope, deliberately:
        - TabItem headers stay English: $sync.currentTab flows from them, and the visible
          tab labels are the nav TextBlocks, which translate normally.
        - Application and AppX package names are product names and stay untranslated. They
          never match a dictionary key, so the walker simply leaves them alone; checkboxes
          carry their data in Tag, not in their label.
        - TextBoxes are skipped: their text is user input, a path, or a status log. The
          creator's path label is compared against a literal by workflow code, so it stays
          whatever the workflow writes.
        - TextBlocks with inline formatting are handled through their Runs: labels built as
          an underlined access-key letter plus the rest are rebuilt from the full string,
          sentences separated by a line break are matched per sentence, and anything without
          a key is left alone.

        Config-rendered tabs are built lazily, in English, after the walker runs. Every tab
        is re-walked when it is built (see Initialize-WinUtilTabContent), so config-rendered
        controls pick the language up there. Baselines recorded on first sight keep apply
        and restore idempotent.

    .PARAMETER Language
        The language code to apply, e.g. "pt-BR" or "en-US". Stored in
        $sync.preferences.language and resolved through config/translations.json.

    .EXAMPLE
        Invoke-WinUtilTranslation -Language "pt-BR"

    #>

    param([string]$Language)

    if (-not $sync.Form) {
        return
    }

    $sync.preferences.language = $Language
    if (Get-Command Save-WinUtilPreferences -ErrorAction SilentlyContinue) { Save-WinUtilPreferences }

    $targets = @($sync.Form)
    foreach ($popupName in @("ThemePopup", "SettingsPopup", "FontScalingPopup", "LanguagePopup", "selectedAppsPopup")) {
        if ($sync[$popupName]) {
            $targets += $sync[$popupName]
        }
    }
    # Tab content lives inside a TabControl whose custom template prevents the visual-tree
    # walker from reaching into the content area. Walk the named grids directly so config-
    # rendered controls (labels, checkboxes, buttons, toggles) are always covered.
    foreach ($gridName in @("tweakspanel", "featurespanel", "appspanel", "appscategory", "appxpanel")) {
        $grid = $sync.Form.FindName($gridName)
        if ($grid) { $targets += $grid }
    }

    $table = $sync.configs.translations.$Language
    if (-not $table -and $Language -ne "en-US") {
        Write-WinUtilLog -Component "UI" -Message "No translation table for '$Language'; reverting to English."
        $Language = "en-US"
        $table = $null
    }
    $isTranslated = $Language -ne "en-US"
    $changed = 0

    # Dictionary lookup with one decoration fallback: the FOSS note run is rendered with a
    # leading space the config key does not have. Re-attaches the space to the translation.
    $lookup = {
        param($English)

        if (-not $English -or -not $table) {
            return $null
        }
        $prop = $table.PSObject.Properties[$English]
        $translated = if ($prop) { $prop.Value } else { $null }
        if ((-not $translated) -and $English.StartsWith(" ")) {
            $innerProp = $table.PSObject.Properties[$English.Substring(1)]
            $inner = if ($innerProp) { $innerProp.Value } else { $null }
            if ($inner) {
                return " $inner"
            }
        }
        return $translated
    }

    # Resolves the value for one English string: the translation when the language has one,
    # otherwise the recorded English baseline (a restore, or a coverage gap on re-apply).
    # Returns $null when the property should be left alone.
    $resolveValue = {
        param($English)

        $translation = & $lookup $English
        if ($translation) {
            if ($translation -cne $English) {
                return $translation
            }
            return $null
        }
        if ($English) {
            return $English
        }
        return $null
    }

    $visited = [System.Collections.Generic.HashSet[object]]::new()
    foreach ($root in $targets) {
        if (-not $root) { continue }

        $queue = [System.Collections.Generic.Queue[object]]::new()
        $queue.Enqueue($root)

        while ($queue.Count -gt 0) {
            $element = $queue.Dequeue()
            if (-not $visited.Add($element)) {
                continue
            }

            # Popups are logical children of their placement button, the rest of the tree is
            # visual; walking both makes one code path cover everything.
            try {
                $visualCount = [Windows.Media.VisualTreeHelper]::GetChildrenCount($element)
                for ($i = 0; $i -lt $visualCount; $i++) {
                    $child = [Windows.Media.VisualTreeHelper]::GetChild($element, $i)
                    if ($child -and -not $visited.Contains($child)) { $queue.Enqueue($child) }
                }
            } catch {
                # Not a visual or unsupported type; fall back to walking Content property.
            }
            try {
                foreach ($child in @($element.LogicalChildren)) {
                    if ($child -is [Windows.FrameworkElement] -and -not $visited.Contains($child)) {
                        $queue.Enqueue($child)
                    }
                }
            } catch {
                # No logical children.
            }
            # Fallback: if visual-tree walk found nothing, walk through Content property
            # of ContentControl elements (covers ContentPresenter-based templates).
            if ($element -is [Windows.Controls.ContentControl] -and $element.Content -is [Windows.FrameworkElement]) {
                if (-not $visited.Contains($element.Content)) {
                    $queue.Enqueue($element.Content)
                }
            }
            if ($element -is [Windows.Controls.ItemsControl]) {
                foreach ($item in $element.Items) {
                    if ($item -is [Windows.FrameworkElement] -and -not $visited.Contains($item)) {
                        $queue.Enqueue($item)
                    }
                }
            }

            # ToolTips declared as elements hold their own content subtree and are not
            # reachable through logical or visual children until opened.
            if ($element.ToolTip -is [Windows.Controls.ToolTip] -and -not $visited.Contains($element.ToolTip)) {
                $queue.Enqueue($element.ToolTip)
            }

            # Static XAML TextBlocks with a Text property, e.g. the updates bullets and the
            # offline banner.
            if ($element -is [Windows.Controls.TextBlock]) {
                if ($element.Text) {
                    $english = Get-WinUtilTextBaseline -Control $element -Kind "Text" -Current $element.Text
                    $translated = $table.PSObject.Properties[$english].Value
                    $value = & $resolveValue $english
                    if ($null -ne $value) {
                        $element.Text = $value
                        $changed++
                    }
                }
                elseif ($element.Inlines.Count -gt 0) {
                    # Recursively collect all Run objects from the inline tree, including
                    # those nested inside Underline, Bold, Italic, etc. Nav buttons use
                    # <Underline>I</Underline>nstall which hides the first Run inside a
                    # container, so a flat Where-Object would miss it. Uses a stack (DFS)
                    # to preserve document order.
                    $runs = [System.Collections.Generic.List[object]]::new()
                    $inlineStack = [System.Collections.Generic.Stack[object]]::new()
                    # Push in reverse so the first inline is processed first.
                    $inlinesArr = @($element.Inlines)
                    for ($idx = $inlinesArr.Count - 1; $idx -ge 0; $idx--) {
                        $inlineStack.Push($inlinesArr[$idx])
                    }
                    while ($inlineStack.Count -gt 0) {
                        $il = $inlineStack.Pop()
                        if ($il -is [Windows.Documents.Run]) {
                            $runs.Add($il)
                        }
                        try {
                            if ($il.Inlines -and $il.Inlines.Count -gt 0) {
                                $childArr = @($il.Inlines)
                                for ($idx = $childArr.Count - 1; $idx -ge 0; $idx--) {
                                    $inlineStack.Push($childArr[$idx])
                                }
                            }
                        } catch {
                            # No Inlines sub-collection.
                        }
                    }

                    # Nav buttons render an underlined access-key letter plus the rest, which
                    # does not decompose into per-run keys. Try the full label first.
                    $fullText = -join ($runs | ForEach-Object { $_.Text })
                    $english = Get-WinUtilTextBaseline -Control $element -Kind "Inlines" -Current $fullText
                    $value = & $resolveValue $english

                    if ($null -ne $value) {
                        # Keep the access-key underline on the first character. The shortcut
                        # itself is wired by key and does not follow the translation.
                        $runs[0].Text = $value.Substring(0, 1)
                        if ($runs.Count -ge 2) {
                            $runs[1].Text = $value.Substring(1)
                            for ($r = 2; $r -lt $runs.Count; $r++) {
                                $runs[$r].Text = ""
                            }
                        }
                        $changed++
                    }
                    else {
                        # Sentences separated by a line break are one Run each and match
                        # per-sentence keys, e.g. the tweaks note.
                        foreach ($run in $runs) {
                            if (-not $run.Text) { continue }
                            $runEnglish = Get-WinUtilTextBaseline -Control $run -Kind "Run" -Current $run.Text
                            $runValue = & $resolveValue $runEnglish
                            if ($null -ne $runValue) {
                                $run.Text = $runValue
                                $changed++
                            }
                        }
                    }
                }
                continue
            }

            # Menu item headers, e.g. the theme, settings, and language menus. TabItem is a
            # HeaderedContentControl and is deliberately not matched: its header feeds
            # $sync.currentTab and stays English.
            if ($element -is [Windows.Controls.HeaderedItemsControl]) {
                if ($element.Header -is [string] -and $element.Header) {
                    $english = Get-WinUtilTextBaseline -Control $element -Kind "Header" -Current $element.Header
                    $translated = $table.PSObject.Properties[$english].Value
                    $value = & $resolveValue $english
                    if ($null -ne $value) {
                        $element.Header = $value
                        $changed++
                    }
                }
                continue
            }

            # Buttons and labels rendered from config: only exact dictionary keys are
            # translated, so application names and preset-key tooltips pass through.
            if ($element -is [Windows.Controls.ContentControl] -and $element.Content -is [string]) {
                if ($element.Tag -eq "CategoryToggleButton" -or ($element -is [Windows.Controls.Label] -and $element.Content -match '^[+-]\s+')) {
                    $prefix = if ($element.Content -match '^([+-]\s*)') { $matches[1] } else { "- " }
                    $englishFull = Get-WinUtilTextBaseline -Control $element -Kind "Content" -Current $element.Content
                    $englishCat = $englishFull -replace '^[+-]\s*', ''
                    $translatedCat = & $resolveValue $englishCat
                    if ($null -ne $translatedCat) {
                        $element.Content = "$prefix$translatedCat"
                        $changed++
                    }
                    continue
                }
                $english = Get-WinUtilTextBaseline -Control $element -Kind "Content" -Current $element.Content
                $translated = $table.PSObject.Properties[$english].Value
                $value = & $resolveValue $english
                if ($null -ne $value) {
                    $element.Content = $value
                    $changed++
                }
            }

            # Tooltip as string property, e.g. title-bar buttons and config-rendered entries.
            if ($element.ToolTip -is [string] -and $element.ToolTip) {
                $toolTipText = $element.ToolTip
                if ($toolTipText -match '(?s)^(?<Desc>.*?)(?<Suffix>\r?\n\r?\nPreset key:\s*.*)$') {
                    $desc = $matches['Desc']
                    $suffix = $matches['Suffix']
                    $englishDesc = Get-WinUtilTextBaseline -Control $element -Kind "ToolTip" -Current $desc
                    $value = & $resolveValue $englishDesc
                    if ($null -ne $value) {
                        $element.ToolTip = "$value$suffix"
                        $changed++
                    }
                }
                elseif ($toolTipText -match '^Preset key:\s*.*$') {
                    # Preset key only, no description text to translate.
                }
                else {
                    $english = Get-WinUtilTextBaseline -Control $element -Kind "ToolTip" -Current $toolTipText
                    $value = & $resolveValue $english
                    if ($null -ne $value) {
                        $element.ToolTip = $value
                        $changed++
                    }
                }
            }
        }
    }

    # The counter is template-built, so it never matches a static key. Rebuild it in the
    # selected language; before the Install tab exists the config label renders verbatim and
    # the next counter update picks the language up.
    if ($sync.WPFselectedAppsButton) {
        $count = if ($sync.selectedApps) { $sync.selectedApps.Count } else { 0 }
        $sync.WPFselectedAppsButton.Content = Get-WinUtilSelectedAppsCountText -Count $count
    }

    # The popup title is a plain bilingual label and does not need per-language text, but the
    # checkmark state of the entries has to follow the selection.
    if ($sync.EnglishLanguageMenuItem) { $sync.EnglishLanguageMenuItem.IsChecked = -not $isTranslated }
    if ($sync.PortugueseLanguageMenuItem) { $sync.PortugueseLanguageMenuItem.IsChecked = $isTranslated }

    if ($isTranslated) {
        Write-WinUtilLog -Component "UI" -Message "Interface translated to '$Language' ($changed strings updated)."
    } else {
        Write-WinUtilLog -Component "UI" -Message "Interface reverted to English ($changed strings updated)."
    }
}
