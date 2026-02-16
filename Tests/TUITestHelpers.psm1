# TUITestHelpers - tmux-based test harness for TUI integration testing
# Provides Playwright-like primitives for terminal UI testing

#region Timeout Scaling

$script:TimeoutScale = if ($env:TUI_TEST_TIMEOUT_SCALE) {
    [double]$env:TUI_TEST_TIMEOUT_SCALE
} else {
    1.0
}

function Get-ScaledTimeout {
    param([int]$Seconds)
    [int][Math]::Ceiling($Seconds * $script:TimeoutScale)
}

#endregion

#region Core Primitives

function Start-TUISession {
    <#
    .SYNOPSIS
        Starts a new tmux session running the specified command
    .PARAMETER Name
        Unique session name
    .PARAMETER Command
        Shell command to run inside the session
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Command
    )

    # Kill any leftover session with the same name
    tmux kill-session -t $Name 2>$null

    tmux new-session -d -s $Name -x 120 -y 40 $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create tmux session '$Name'"
    }

    return $Name
}

function Get-TUIScreen {
    <#
    .SYNOPSIS
        Captures the current screen content of a tmux session
    .PARAMETER Name
        The tmux session name
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $lines = tmux capture-pane -t $Name -p
    return $lines
}

function Send-TUIKeys {
    <#
    .SYNOPSIS
        Sends keystrokes to a tmux session
    .PARAMETER Name
        The tmux session name
    .PARAMETER Keys
        Keys to send. Supports tmux key names: Enter, Escape, Tab, C-q, etc.
    .PARAMETER Literal
        Send keys as literal text (uses tmux -l flag). Required for strings
        containing characters that tmux interprets specially (e.g. +).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$Keys,

        [switch]$Literal
    )

    foreach ($key in $Keys) {
        if ($Literal) {
            tmux send-keys -t $Name -l $key
        } else {
            tmux send-keys -t $Name $key
        }
    }
}

function Wait-ForTUIText {
    <#
    .SYNOPSIS
        Polls screen content until the specified text appears or timeout
    .PARAMETER Name
        The tmux session name
    .PARAMETER Text
        Text to search for in the screen output
    .PARAMETER TimeoutSeconds
        Maximum time to wait (default 15, scaled by TUI_TEST_TIMEOUT_SCALE)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Text,

        [int]$TimeoutSeconds = 15
    )

    $scaled = Get-ScaledTimeout -Seconds $TimeoutSeconds
    $deadline = (Get-Date).AddSeconds($scaled)

    while ((Get-Date) -lt $deadline) {
        $screen = Get-TUIScreen -Name $Name
        $joined = $screen -join "`n"
        if ($joined -match [regex]::Escape($Text)) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    return $false
}

function Wait-ForTUITextGone {
    <#
    .SYNOPSIS
        Polls screen content until the specified text disappears or timeout
    .PARAMETER Name
        The tmux session name
    .PARAMETER Text
        Text that should disappear from the screen
    .PARAMETER TimeoutSeconds
        Maximum time to wait (default 15, scaled by TUI_TEST_TIMEOUT_SCALE)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Text,

        [int]$TimeoutSeconds = 15
    )

    $scaled = Get-ScaledTimeout -Seconds $TimeoutSeconds
    $deadline = (Get-Date).AddSeconds($scaled)

    while ((Get-Date) -lt $deadline) {
        $screen = Get-TUIScreen -Name $Name
        $joined = $screen -join "`n"
        if ($joined -notmatch [regex]::Escape($Text)) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    return $false
}

function Stop-TUISession {
    <#
    .SYNOPSIS
        Kills a tmux session
    .PARAMETER Name
        The tmux session name
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    tmux kill-session -t $Name 2>$null
}

#endregion

#region Screenshot & Diagnostics

function Save-TUIScreenshot {
    <#
    .SYNOPSIS
        Saves the current screen content to a timestamped file for debugging
    .PARAMETER Name
        The tmux session name
    .PARAMETER Label
        A descriptive label for the screenshot file
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $dir = Join-Path $PSScriptRoot "TestResults"
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeLabel = $Label -replace '[^a-zA-Z0-9_-]', '_'
    $filePath = Join-Path $dir "${timestamp}_${safeLabel}.txt"

    $screen = Get-TUIScreen -Name $Name
    $screen -join "`n" | Set-Content -Path $filePath -Encoding UTF8
    return $filePath
}

function Get-TUICursorPosition {
    <#
    .SYNOPSIS
        Returns the cursor row and column from the tmux session
    .PARAMETER Name
        The tmux session name
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $row = tmux display-message -t $Name -p '#{cursor_y}'
    $col = tmux display-message -t $Name -p '#{cursor_x}'
    return @{ Row = [int]$row; Col = [int]$col }
}

function Assert-TUIRegion {
    <#
    .SYNOPSIS
        Checks whether a regex matches text within a row/col subregion of the screen
    .PARAMETER Name
        The tmux session name
    .PARAMETER StartRow
        Starting row (0-indexed)
    .PARAMETER EndRow
        Ending row (0-indexed, inclusive)
    .PARAMETER Pattern
        Regex pattern to match against the subregion text
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$StartRow,

        [Parameter(Mandatory)]
        [int]$EndRow,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $screen = Get-TUIScreen -Name $Name
    $regionLines = $screen[$StartRow..$EndRow]
    $regionText = $regionLines -join "`n"
    return $regionText -match $Pattern
}

function Get-TUISessionList {
    <#
    .SYNOPSIS
        Lists active tmux sessions matching the test prefix
    .PARAMETER Prefix
        Session name prefix to filter (default: 'psreddittui-test-')
    #>
    param(
        [string]$Prefix = 'psreddittui-test-'
    )

    $sessions = tmux list-sessions -F '#{session_name}' 2>$null
    if ($null -eq $sessions) { return @() }
    return @($sessions | Where-Object { $_ -like "${Prefix}*" })
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Retries a scriptblock N times with delay between attempts
    .PARAMETER ScriptBlock
        The scriptblock to execute
    .PARAMETER MaxRetries
        Maximum number of retries (default 3)
    .PARAMETER DelaySeconds
        Delay between retries in seconds (default 2)
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxRetries = 3,

        [int]$DelaySeconds = 2
    )

    $attempt = 0
    while ($attempt -le $MaxRetries) {
        try {
            return & $ScriptBlock
        } catch {
            $attempt++
            if ($attempt -gt $MaxRetries) { throw }
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

#endregion

#region Focus Navigation Helpers

function Focus-TUIPostsList {
    <#
    .SYNOPSIS
        Navigates focus to the posts ListView from the initial favorites focus.
        In Terminal.Gui v1, the initial focus after load is on the favorites list.
        Three forward Tabs cycle: favoritesList -> addFavBtn -> removeFavBtn -> postsListView
        (contentFrame re-focuses its last focused child set by SetFocus).
    .PARAMETER Name
        The tmux session name
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    for ($i = 0; $i -lt 3; $i++) {
        Send-TUIKeys -Name $Name -Keys "Tab"
        Start-Sleep -Milliseconds 200
    }
}

function Focus-TUISubredditField {
    <#
    .SYNOPSIS
        Navigates focus from the posts ListView to the subreddit input field.
        Uses backward Tab (Shift+Tab) to cycle through contentFrame children:
        postsListView -> searchGlobalCheck -> searchBtn -> searchInput -> sortCombo -> loadBtn -> subredditInput
    .PARAMETER Name
        The tmux session name
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    for ($i = 0; $i -lt 6; $i++) {
        Send-TUIKeys -Name $Name -Keys "BTab"
        Start-Sleep -Milliseconds 150
    }
}

function Focus-TUISortCombo {
    <#
    .SYNOPSIS
        Navigates focus from the posts ListView to the sort ComboBox.
        BTabs from postsListView: searchGlobalCheck -> searchBtn -> searchInput -> sortCombo
    .PARAMETER Name
        The tmux session name
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    for ($i = 0; $i -lt 4; $i++) {
        Send-TUIKeys -Name $Name -Keys "BTab"
        Start-Sleep -Milliseconds 150
    }
}

function Focus-TUISearchInput {
    <#
    .SYNOPSIS
        Navigates focus from the posts ListView to the search input field.
        BTabs from postsListView: searchGlobalCheck -> searchBtn -> searchInput
    .PARAMETER Name
        The tmux session name
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    for ($i = 0; $i -lt 3; $i++) {
        Send-TUIKeys -Name $Name -Keys "BTab"
        Start-Sleep -Milliseconds 150
    }
}

function Set-TUISubreddit {
    <#
    .SYNOPSIS
        Clears the subreddit field, types a new value, and loads it.
        Assumes focus is currently on the subreddit input field.
    .PARAMETER Name
        The tmux session name
    .PARAMETER Subreddit
        The subreddit name to type
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Subreddit
    )

    # Select all text in the field and delete it
    Send-TUIKeys -Name $Name -Keys "End"
    Start-Sleep -Milliseconds 100
    for ($i = 0; $i -lt 30; $i++) {
        Send-TUIKeys -Name $Name -Keys "BSpace"
        Start-Sleep -Milliseconds 20
    }

    # Type the new subreddit name (use -Literal for special chars like +)
    Send-TUIKeys -Name $Name -Keys $Subreddit -Literal
    Start-Sleep -Milliseconds 200

    # Tab to Load button and press Enter
    Send-TUIKeys -Name $Name -Keys "Tab"
    Start-Sleep -Milliseconds 200
    Send-TUIKeys -Name $Name -Keys "Enter"
}

#endregion

Export-ModuleMember -Function @(
    'Start-TUISession'
    'Get-TUIScreen'
    'Send-TUIKeys'
    'Wait-ForTUIText'
    'Wait-ForTUITextGone'
    'Stop-TUISession'
    'Save-TUIScreenshot'
    'Get-TUICursorPosition'
    'Assert-TUIRegion'
    'Get-TUISessionList'
    'Invoke-WithRetry'
    'Focus-TUIPostsList'
    'Focus-TUISubredditField'
    'Focus-TUISortCombo'
    'Focus-TUISearchInput'
    'Set-TUISubreddit'
)
