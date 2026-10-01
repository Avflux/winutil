function Show-WinUtilMessage {
    <#
    .SYNOPSIS
        Shows a WinUtil message box and returns the selected result.

    .DESCRIPTION
        Message boxes need the interface thread, so this marshals onto it and can therefore be
        called from a job body as well as from an event handler. Every prompt is also written to
        the session log so the log shows what the user was asked and not just what happened next.

        With no window there is nobody to click, so nothing is shown. A modal put up in that
        state never returns and takes the worker with it.
    #>
    param (
        [string]$Message,
        [string]$Title = "Winutil",
        $Button = "OK",
        $Icon = "Information"
    )

    # Translate the title and message through the same dictionary the walker uses, so
    # any caller can pass English strings and they are rendered in the selected language.
    # Strings with dynamic content fall back to English when no template key matches.
    $Message = Get-WinUtilTranslation -Text $Message
    $Title = Get-WinUtilTranslation -Text $Title

    Write-WinUtilLog -Component "Dialog" -Message "$Title : $(($Message -split "`n" | ForEach-Object { $_.Trim() }) -join ' | ')"

    if (-not (Test-WinUtilUIAlive)) {
        # Anything with a choice is answered with the one that does not go ahead, so a prompt
        # nobody saw can never stand in for consent
        $unattended = if ("$Button" -eq "OK") { "OK" } else { "No" }
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window to ask on, answering '$unattended' for: $Title"
        return $unattended
    }

    return Invoke-WPFUIThread -PassThru -Parameters @{
        Message = $Message
        Title = $Title
        Button = $Button
        Icon = $Icon
    } -ScriptBlock {
        param($Message, $Title, $Button, $Icon)

        [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Icon)
    }
}
