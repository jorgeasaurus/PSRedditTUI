# PSRedditTUI - PowerShell Reddit Terminal UI Module
# Requires PowerShell Core 7+

#region Logging

$script:LogFile = Join-Path $HOME ".psreddittui.log"
$script:LogLevel = "Debug"  # Debug, Info, Warning, Error

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log entry to the log file
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        The log level (Debug, Info, Warning, Error)
    .PARAMETER Exception
        Optional exception object for error logging
    .PARAMETER ErrorRecord
        Optional ErrorRecord object for detailed error logging
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $levels = @{ 'Debug' = 0; 'Info' = 1; 'Warning' = 2; 'Error' = 3 }
    $currentLevel = $levels[$script:LogLevel]
    $messageLevel = $levels[$Level]

    if ($messageLevel -lt $currentLevel) {
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $caller = (Get-PSCallStack)[1]
    $callerInfo = if ($caller.FunctionName -and $caller.FunctionName -ne '<ScriptBlock>') {
        $caller.FunctionName
    } else {
        "Module"
    }

    $logEntry = "[$timestamp] [$Level] [$callerInfo] $Message"

    # Add exception details
    if ($Exception) {
        $logEntry += "`n  Exception Type: $($Exception.GetType().FullName)"
        $logEntry += "`n  Exception Message: $($Exception.Message)"
        if ($Exception.InnerException) {
            $logEntry += "`n  Inner Exception: $($Exception.InnerException.GetType().Name): $($Exception.InnerException.Message)"
        }
        if ($Exception.StackTrace) {
            $logEntry += "`n  StackTrace:`n    $($Exception.StackTrace -replace "`n", "`n    ")"
        }
    }

    # Add ErrorRecord details (more PowerShell-specific info)
    if ($ErrorRecord) {
        $logEntry += "`n  Error Category: $($ErrorRecord.CategoryInfo.Category)"
        $logEntry += "`n  Error ID: $($ErrorRecord.FullyQualifiedErrorId)"
        $logEntry += "`n  Target Object: $($ErrorRecord.TargetObject)"
        if ($ErrorRecord.InvocationInfo) {
            $logEntry += "`n  Script: $($ErrorRecord.InvocationInfo.ScriptName)"
            $logEntry += "`n  Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
            $logEntry += "`n  Command: $($ErrorRecord.InvocationInfo.MyCommand)"
        }
        if ($ErrorRecord.ScriptStackTrace) {
            $logEntry += "`n  Script StackTrace:`n    $($ErrorRecord.ScriptStackTrace -replace "`n", "`n    ")"
        }
    }

    try {
        $logEntry | Out-File -FilePath $script:LogFile -Append -Encoding utf8
    }
    catch {
        # Silently fail if we can't write to log
    }
}

function Clear-PSRedditTUILog {
    <#
    .SYNOPSIS
        Clears the PSRedditTUI log file
    #>
    [CmdletBinding()]
    param()

    if (Test-Path $script:LogFile) {
        Remove-Item $script:LogFile -Force
        Write-Log -Message "Log file cleared" -Level Info
    }
}

function Get-PSRedditTUILog {
    <#
    .SYNOPSIS
        Gets the contents of the PSRedditTUI log file
    .PARAMETER Tail
        Number of lines to show from the end (default: all)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Tail = 0
    )

    if (Test-Path $script:LogFile) {
        if ($Tail -gt 0) {
            Get-Content $script:LogFile -Tail $Tail
        } else {
            Get-Content $script:LogFile
        }
    } else {
        Write-Warning "Log file not found: $script:LogFile"
    }
}

function Set-PSRedditTUILogLevel {
    <#
    .SYNOPSIS
        Sets the logging level for PSRedditTUI
    .PARAMETER Level
        The log level (Debug, Info, Warning, Error)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level
    )

    $script:LogLevel = $Level
    Write-Log -Message "Log level set to: $Level" -Level Info
}

#endregion

# Module variables
$script:FavoritesFile = Join-Path $HOME ".psreddittui_favorites.json"
$script:Favorites = @()

# Default subreddits to populate on first launch
$script:DefaultFavorites = @(
    'popular',
    'all',
    'powershell',
    'windows',
    'microsoft',
    'technology',
    'news',
    'gaming',
    'lifeprotips',
    'todayilearned',
    'askreddit'
)

Write-Log -Message "Favorites file: $script:FavoritesFile" -Level Debug

#region Reddit API Functions

function Get-RedditData {
    <#
    .SYNOPSIS
        Fetches Reddit data in JSON format
    .DESCRIPTION
        Appends /.json to Reddit URLs and fetches the data
    .PARAMETER Url
        The Reddit URL to fetch (without .json extension)
    .EXAMPLE
        Get-RedditData -Url "https://www.reddit.com/r/powershell"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
    
    try {
        # Add .json to the URL path (before any query string)
        if (-not ($Url -match '\.json')) {
            # Parse URL to insert .json before query string
            if ($Url -match '\?') {
                # URL has query string - insert .json before it
                $Url = $Url -replace '\?', '.json?'
            } else {
                # No query string - just append .json
                $Url = $Url.TrimEnd('/') + '.json'
            }
        }

        Write-Log -Message "Fetching Reddit data from: $Url" -Level Debug
        Write-Verbose "Fetching data from: $Url"

        # Use module version for User-Agent
        $moduleVersion = $MyInvocation.MyCommand.Module.Version
        $userAgent = "PSRedditTUI/$moduleVersion"

        $startTime = Get-Date
        # Use Invoke-WebRequest to get raw response for validation
        $webResponse = Invoke-WebRequest -Uri $Url -Method Get -UserAgent $userAgent
        $duration = ((Get-Date) - $startTime).TotalMilliseconds

        # Log response details
        $statusCode = $webResponse.StatusCode
        $contentType = $webResponse.Headers['Content-Type']
        $contentLength = $webResponse.Content.Length
        Write-Log -Message "Reddit API response: Status=$statusCode, ContentType=$contentType, Size=${contentLength}bytes, Duration=${duration}ms" -Level Debug

        # Get raw content
        $rawContent = $webResponse.Content

        # Log first portion of response for debugging (truncate if too long)
        $previewLength = [Math]::Min($rawContent.Length, 500)
        $preview = $rawContent.Substring(0, $previewLength)
        if ($rawContent.Length -gt 500) {
            $preview += "... [truncated, total: $($rawContent.Length) chars]"
        }
        Write-Log -Message "Response preview: $preview" -Level Debug

        # Check if content type indicates JSON
        if ($contentType -and -not ($contentType -match 'application/json|text/json')) {
            Write-Log -Message "Warning: Unexpected content type '$contentType' - expected JSON" -Level Warning
        }

        # Validate JSON and parse
        try {
            $response = $rawContent | ConvertFrom-Json
            Write-Log -Message "JSON parsed successfully" -Level Debug

            # Log structure info
            if ($response -is [array]) {
                Write-Log -Message "Response is array with $($response.Count) elements" -Level Debug
            } elseif ($response.data) {
                $childCount = if ($response.data.children) { $response.data.children.Count } else { 0 }
                Write-Log -Message "Response has data property with $childCount children" -Level Debug
            }

            return $response
        }
        catch {
            Write-Log -Message "Failed to parse JSON response from: $Url" -Level Error -ErrorRecord $_
            Write-Log -Message "Invalid JSON content: $preview" -Level Error
            Write-Error "Response is not valid JSON: $_"
            return $null
        }
    }
    catch {
        Write-Log -Message "Failed to fetch Reddit data from: $Url" -Level Error -ErrorRecord $_
        Write-Error "Failed to fetch Reddit data: $_"
        return $null
    }
}

function Get-RedditPosts {
    <#
    .SYNOPSIS
        Gets posts from a subreddit
    .PARAMETER Subreddit
        The subreddit name (without r/)
    .PARAMETER Sort
        Sort order (hot, new, top, rising)
    .PARAMETER Time
        Time filter for 'top' sort (hour, day, week, month, year, all)
    .EXAMPLE
        Get-RedditPosts -Subreddit "powershell" -Sort "hot"
    .EXAMPLE
        Get-RedditPosts -Subreddit "powershell" -Sort "top" -Time "week"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z0-9_-]+$')]
        [string]$Subreddit,

        [Parameter(Mandatory = $false)]
        [ValidateSet('hot', 'new', 'top', 'rising')]
        [string]$Sort = 'hot',

        [Parameter(Mandatory = $false)]
        [ValidateSet('hour', 'day', 'week', 'month', 'year', 'all')]
        [string]$Time = 'day'
    )

    Write-Log -Message "Getting posts from r/$Subreddit (sort: $Sort, time: $Time)" -Level Info

    $url = "https://www.reddit.com/r/$Subreddit/$Sort"

    # Add time filter for 'top' sort
    if ($Sort -eq 'top') {
        $url += "?t=$Time"
    }
    $data = Get-RedditData -Url $url

    if ($data -and $data.data -and $data.data.children) {
        $postCount = $data.data.children.Count
        Write-Log -Message "Retrieved $postCount posts from r/$Subreddit" -Level Debug
        return $data.data.children | ForEach-Object {
            [PSCustomObject]@{
                Title = $_.data.title
                Author = $_.data.author
                Score = $_.data.score
                Subreddit = $_.data.subreddit
                Url = "https://www.reddit.com$($_.data.permalink)"
                Permalink = $_.data.permalink
                NumComments = $_.data.num_comments
                Created = [DateTimeOffset]::FromUnixTimeSeconds($_.data.created_utc).LocalDateTime
                SelfText = $_.data.selftext
                IsLink = -not [string]::IsNullOrEmpty($_.data.url) -and $_.data.url -ne $_.data.permalink
                LinkUrl = $_.data.url
            }
        }
    }

    return @()
}

function Get-RedditComments {
    <#
    .SYNOPSIS
        Gets comments for a Reddit post
    .PARAMETER Permalink
        The permalink of the post (e.g., "/r/powershell/comments/abc123/title/")
    .PARAMETER Limit
        Maximum number of comments to retrieve (default: 50)
    .EXAMPLE
        Get-RedditComments -Permalink "/r/powershell/comments/abc123/my_post/"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Permalink,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 50
    )

    Write-Log -Message "Getting comments for: $Permalink" -Level Info

    $url = "https://www.reddit.com$Permalink"
    $data = Get-RedditData -Url $url

    if ($data -and $data.Count -ge 2) {
        # First element is the post, second element contains comments
        $commentsData = $data[1]

        if ($commentsData.data -and $commentsData.data.children) {
            $comments = @()
            $commentCount = 0

            foreach ($child in $commentsData.data.children) {
                if ($child.kind -eq 't1' -and $commentCount -lt $Limit) {
                    $comment = ConvertTo-CommentObject -CommentData $child.data -Depth 0
                    if ($comment) {
                        $comments += $comment
                        $commentCount++
                    }
                }
            }

            Write-Log -Message "Retrieved $($comments.Count) top-level comments" -Level Debug
            return $comments
        }
    }

    Write-Log -Message "No comments found for: $Permalink" -Level Debug
    return @()
}

function Search-Reddit {
    <#
    .SYNOPSIS
        Searches Reddit for posts
    .PARAMETER Query
        The search query
    .PARAMETER Subreddit
        Optional subreddit to search within (omit for global search)
    .PARAMETER Sort
        Sort order for results (relevance, hot, top, new, comments)
    .PARAMETER Time
        Time filter (hour, day, week, month, year, all)
    .EXAMPLE
        Search-Reddit -Query "powershell scripts"
    .EXAMPLE
        Search-Reddit -Query "automation" -Subreddit "powershell"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [string]$Subreddit,

        [Parameter(Mandatory = $false)]
        [ValidateSet('relevance', 'hot', 'top', 'new', 'comments')]
        [string]$Sort = 'relevance',

        [Parameter(Mandatory = $false)]
        [ValidateSet('hour', 'day', 'week', 'month', 'year', 'all')]
        [string]$Time = 'all'
    )

    Write-Log -Message "Searching Reddit: '$Query' (subreddit: $Subreddit, sort: $Sort, time: $Time)" -Level Info

    # URL encode the query
    $encodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)

    # Build URL
    if ($Subreddit) {
        $url = "https://www.reddit.com/r/$Subreddit/search.json?q=$encodedQuery&restrict_sr=on&sort=$Sort&t=$Time"
    } else {
        $url = "https://www.reddit.com/search.json?q=$encodedQuery&sort=$Sort&t=$Time"
    }

    try {
        Write-Log -Message "Search URL: $url" -Level Debug

        # Use module version for User-Agent
        $moduleVersion = $MyInvocation.MyCommand.Module.Version
        $userAgent = "PSRedditTUI/$moduleVersion"

        $startTime = Get-Date
        $response = Invoke-RestMethod -Uri $url -Method Get -UserAgent $userAgent
        $duration = ((Get-Date) - $startTime).TotalMilliseconds

        Write-Log -Message "Search completed in ${duration}ms" -Level Debug

        if ($response -and $response.data -and $response.data.children) {
            $resultCount = $response.data.children.Count
            Write-Log -Message "Search returned $resultCount results" -Level Info

            return $response.data.children | ForEach-Object {
                [PSCustomObject]@{
                    Title = $_.data.title
                    Author = $_.data.author
                    Score = $_.data.score
                    Subreddit = $_.data.subreddit
                    Url = "https://www.reddit.com$($_.data.permalink)"
                    Permalink = $_.data.permalink
                    NumComments = $_.data.num_comments
                    Created = [DateTimeOffset]::FromUnixTimeSeconds($_.data.created_utc).LocalDateTime
                    SelfText = $_.data.selftext
                    IsLink = -not [string]::IsNullOrEmpty($_.data.url) -and $_.data.url -ne $_.data.permalink
                    LinkUrl = $_.data.url
                }
            }
        }

        return @()
    }
    catch {
        Write-Log -Message "Search failed for query: '$Query' (subreddit: $Subreddit)" -Level Error -ErrorRecord $_
        Write-Error "Failed to search Reddit: $_"
        return @()
    }
}

function ConvertTo-CommentObject {
    <#
    .SYNOPSIS
        Converts Reddit comment data to a PowerShell object (recursive for replies)
    #>
    param(
        [Parameter(Mandatory = $true)]
        $CommentData,

        [Parameter(Mandatory = $false)]
        [int]$Depth = 0
    )

    if (-not $CommentData.body) {
        return $null
    }

    $replies = @()

    # Process replies if they exist
    if ($CommentData.replies -and $CommentData.replies.data -and $CommentData.replies.data.children) {
        foreach ($reply in $CommentData.replies.data.children) {
            if ($reply.kind -eq 't1') {
                $replyObj = ConvertTo-CommentObject -CommentData $reply.data -Depth ($Depth + 1)
                if ($replyObj) {
                    $replies += $replyObj
                }
            }
        }
    }

    return [PSCustomObject]@{
        Author = $CommentData.author
        Body = $CommentData.body
        Score = $CommentData.score
        Created = [DateTimeOffset]::FromUnixTimeSeconds($CommentData.created_utc).LocalDateTime
        Depth = $Depth
        Replies = $replies
        IsOP = $CommentData.is_submitter
    }
}

#endregion

#region Favorites Management

function Get-Favorites {
    <#
    .SYNOPSIS
        Loads favorites from local storage
    .DESCRIPTION
        Loads favorites from the local JSON file. If the file doesn't exist (first launch),
        it creates the file with a default set of popular subreddits.
    #>
    [CmdletBinding()]
    param()

    Write-Log -Message "Loading favorites from: $script:FavoritesFile" -Level Debug

    if (Test-Path $script:FavoritesFile) {
        try {
            $loadedFavorites = Get-Content $script:FavoritesFile -Raw | ConvertFrom-Json -NoEnumerate

            if ($null -eq $loadedFavorites) {
                $script:Favorites = @()
                Write-Log -Message "Favorites file was empty" -Level Debug
            }
            else {
                # Always wrap in array to handle single-element arrays
                $script:Favorites = @($loadedFavorites)
                Write-Log -Message "Loaded $($script:Favorites.Count) favorites: $($script:Favorites -join ', ')" -Level Info
            }
            # Use Write-Output -NoEnumerate to prevent unwrapping
            Write-Output -NoEnumerate $script:Favorites
            return
        }
        catch {
            Write-Log -Message "Failed to load favorites from: $script:FavoritesFile" -Level Error -ErrorRecord $_
            Write-Warning "Failed to load favorites: $_"
            $script:Favorites = @()
        }
    } else {
        # First launch - populate with default subreddits
        Write-Log -Message "Favorites file does not exist - populating with defaults" -Level Info
        $script:Favorites = $script:DefaultFavorites.Clone()

        # Save defaults to file
        try {
            Save-Favorites
            Write-Log -Message "Created favorites file with $($script:Favorites.Count) default subreddits: $($script:Favorites -join ', ')" -Level Info
            Write-Verbose "First launch: Populated favorites with default subreddits"
        }
        catch {
            Write-Log -Message "Failed to save default favorites" -Level Error -ErrorRecord $_
        }

        # Use Write-Output -NoEnumerate to prevent unwrapping
        Write-Output -NoEnumerate $script:Favorites
        return
    }

    return @()
}

function Save-Favorites {
    <#
    .SYNOPSIS
        Saves favorites to local storage
    #>
    [CmdletBinding()]
    param()

    Write-Log -Message "Saving $($script:Favorites.Count) favorites to: $script:FavoritesFile" -Level Debug

    try {
        if ($script:Favorites.Count -eq 0) {
            # Save empty array explicitly
            '[]' | Set-Content $script:FavoritesFile
        }
        else {
            $script:Favorites | ConvertTo-Json -Depth 10 | Set-Content $script:FavoritesFile
        }
        Write-Log -Message "Favorites saved successfully" -Level Info
        Write-Verbose "Favorites saved to $script:FavoritesFile"
    }
    catch {
        Write-Log -Message "Failed to save favorites to: $script:FavoritesFile" -Level Error -ErrorRecord $_
        Write-Error "Failed to save favorites: $_"
    }
}

function Add-Favorite {
    <#
    .SYNOPSIS
        Adds a subreddit to favorites
    .PARAMETER Subreddit
        The subreddit name to add
    .PARAMETER PassThru
        Return an object representing the added favorite
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subreddit,

        [Parameter()]
        [switch]$PassThru
    )

    Write-Log -Message "Add-Favorite called with: $Subreddit" -Level Debug

    # Strip r/ prefix if present and normalize to lowercase
    $normalizedSubreddit = $Subreddit.ToLower() -replace '^r/', ''

    # Check if already exists (case-insensitive)
    $exists = $script:Favorites | Where-Object { $_.ToLower() -eq $normalizedSubreddit }

    if (-not $exists) {
        $script:Favorites += $normalizedSubreddit
        Save-Favorites
        Write-Log -Message "Added '$normalizedSubreddit' to favorites" -Level Info

        if ($PassThru) {
            [PSCustomObject]@{
                Subreddit = $normalizedSubreddit
                Action = 'Added'
                Timestamp = Get-Date
            }
        }
    }
    else {
        Write-Log -Message "'$normalizedSubreddit' already exists in favorites" -Level Debug

        if ($PassThru) {
            [PSCustomObject]@{
                Subreddit = $normalizedSubreddit
                Action = 'AlreadyExists'
                Timestamp = Get-Date
            }
        }
    }
}

function Remove-Favorite {
    <#
    .SYNOPSIS
        Removes a subreddit from favorites
    .PARAMETER Subreddit
        The subreddit name to remove
    .PARAMETER PassThru
        Return an object representing the removed favorite
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subreddit,

        [Parameter()]
        [switch]$PassThru
    )

    Write-Log -Message "Remove-Favorite called with: $Subreddit" -Level Debug

    # Strip r/ prefix if present and normalize to lowercase
    $normalizedSubreddit = $Subreddit.ToLower() -replace '^r/', ''

    # Check if exists (case-insensitive)
    $exists = $script:Favorites | Where-Object { $_.ToLower() -eq $normalizedSubreddit }

    if ($exists) {
        # Ensure we always get an array, even if empty
        $filtered = @($script:Favorites | Where-Object { $_.ToLower() -ne $normalizedSubreddit })
        $script:Favorites = $filtered
        Save-Favorites
        Write-Log -Message "Removed '$normalizedSubreddit' from favorites" -Level Info

        if ($PassThru) {
            [PSCustomObject]@{
                Subreddit = $normalizedSubreddit
                Action = 'Removed'
                Timestamp = Get-Date
            }
        }
    }
    else {
        Write-Log -Message "'$normalizedSubreddit' not found in favorites" -Level Debug

        if ($PassThru) {
            [PSCustomObject]@{
                Subreddit = $normalizedSubreddit
                Action = 'NotFound'
                Timestamp = Get-Date
            }
        }
    }
}

#endregion

#region Helper Functions

#endregion

#region Terminal UI

function Show-RedditTUI {
    <#
    .SYNOPSIS
        Launches the Terminal UI for browsing Reddit
    .DESCRIPTION
        Opens an interactive Terminal UI using Spectre.Console for browsing Reddit with a menu-based interface
    .PARAMETER InitialSubreddit
        The subreddit to load initially (default: "popular")
    .EXAMPLE
        Show-RedditTUI
    .EXAMPLE
        Show-RedditTUI -InitialSubreddit "powershell"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InitialSubreddit = "popular"
    )
    
    Write-Log -Message "Show-RedditTUI starting with initial subreddit: $InitialSubreddit" -Level Info

    # Check if PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole -ListAvailable)) {
        Write-Log -Message "PwshSpectreConsole module not found" -Level Error
        Write-Error "PwshSpectreConsole module is required. Install it with: Install-Module PwshSpectreConsole -Scope CurrentUser"
        return
    }

    # Import module if not already loaded
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        Import-Module PwshSpectreConsole
    }

    # Load favorites
    Get-Favorites | Out-Null

    # Initialize state
    $script:CurrentSubreddit = $InitialSubreddit
    $script:CurrentSort = "hot"
    $script:CurrentTime = "day"
    $script:CurrentPosts = @()
    $script:Running = $true

    Write-SpectreHost "`n[bold cyan]PSRedditTUI - Reddit Terminal Browser[/]`n" -NoNewline

    # Main loop
    while ($script:Running) {
        try {
            # Show main menu
            $mainChoice = Read-SpectreSelection -Title "[bold yellow]Main Menu[/]" -Choices @(
                "📖 Browse Subreddit: r/$($script:CurrentSubreddit)",
                "⭐ Manage Favorites",
                "🔍 Search Reddit",
                "⚙️  Settings",
                "❌ Exit"
            ) -Color "Cyan"

            switch -Wildcard ($mainChoice) {
                "📖 Browse*" {
                    Show-BrowseSubredditMenu
                }
                "⭐ Manage*" {
                    Show-FavoritesMenu
                }
                "🔍 Search*" {
                    Show-SearchMenu
                }
                "⚙️  Settings*" {
                    Show-SettingsMenu
                }
                "❌ Exit*" {
                    $script:Running = $false
                    Write-SpectreHost "`n[green]Thanks for using PSRedditTUI! 👋[/]`n"
                }
            }
        }
        catch {
            Write-Log -Message "Error in main menu loop" -Level Error -ErrorRecord $_
            Write-SpectreHost "`n[red]Error: $_[/]`n"
            Start-Sleep -Seconds 2
        }
    }

    Write-Log -Message "Show-RedditTUI exiting normally" -Level Info
}

function Show-BrowseSubredditMenu {
    <#
    .SYNOPSIS
        Shows the browse subreddit submenu
    #>
    [CmdletBinding()]
    param()

    $back = $false
    while (-not $back) {
        try {
            $choices = @(
                "📋 View Posts (Sort: $($script:CurrentSort)$(if ($script:CurrentSort -eq 'top') { "/$($script:CurrentTime)" }))",
                "🔄 Change Subreddit",
                "📊 Change Sort",
                "⬅️  Back to Main Menu"
            )

            $choice = Read-SpectreSelection -Title "[bold yellow]Browse r/$($script:CurrentSubreddit)[/]" -Choices $choices -Color "Cyan"

            switch -Wildcard ($choice) {
                "📋 View Posts*" {
                    Show-PostsList
                }
                "🔄 Change Subreddit*" {
                    $newSub = Read-SpectreText -Prompt "Enter subreddit name" -DefaultAnswer $script:CurrentSubreddit
                    if (-not [string]::IsNullOrWhiteSpace($newSub)) {
                        $script:CurrentSubreddit = $newSub -replace '^r/', ''
                        Write-Log -Message "Changed subreddit to: $($script:CurrentSubreddit)" -Level Info
                    }
                }
                "📊 Change Sort*" {
                    $sortChoice = Read-SpectreSelection -Title "Select Sort Order" -Choices @("hot", "new", "top", "rising") -Color "Green"
                    $script:CurrentSort = $sortChoice
                    
                    if ($sortChoice -eq "top") {
                        $timeChoice = Read-SpectreSelection -Title "Select Time Filter" -Choices @("hour", "day", "week", "month", "year", "all") -Color "Green"
                        $script:CurrentTime = $timeChoice
                    }
                    
                    Write-Log -Message "Changed sort to: $($script:CurrentSort)$(if ($script:CurrentSort -eq 'top') { "/$($script:CurrentTime)" })" -Level Info
                }
                "⬅️  Back*" {
                    $back = $true
                }
            }
        }
        catch {
            Write-Log -Message "Error in browse menu" -Level Error -ErrorRecord $_
            Write-SpectreHost "`n[red]Error: $_[/]`n"
            Start-Sleep -Seconds 2
        }
    }
}

function Show-PostsList {
    <#
    .SYNOPSIS
        Shows the list of posts for the current subreddit
    #>
    [CmdletBinding()]
    param()

    Write-SpectreHost "`n[yellow]Loading posts from r/$($script:CurrentSubreddit)...[/]`n"

    try {
        $script:CurrentPosts = Get-RedditPosts -Subreddit $script:CurrentSubreddit -Sort $script:CurrentSort -Time $script:CurrentTime

        if ($script:CurrentPosts.Count -eq 0) {
            Write-SpectreHost "[yellow]No posts found.[/]`n"
            Start-Sleep -Seconds 2
            return
        }

        # Create table for display
        $table = Format-SpectreTable -Data $script:CurrentPosts -Property @(
            @{Label = "Score"; Expression = { "⬆ $($_.Score)" }},
            @{Label = "Comments"; Expression = { "💬 $($_.NumComments)" }},
            @{Label = "Title"; Expression = { 
                if ($_.Title.Length -gt 70) {
                    $_.Title.Substring(0, 67) + "..."
                } else {
                    $_.Title
                }
            }},
            @{Label = "Author"; Expression = { "u/$($_.Author)" }}
        ) -Border Rounded -Color Cyan

        Write-SpectreHost $table

        # Create menu choices from posts
        $postChoices = for ($i = 0; $i -lt [Math]::Min($script:CurrentPosts.Count, 20); $i++) {
            $post = $script:CurrentPosts[$i]
            $title = if ($post.Title.Length -gt 60) {
                $post.Title.Substring(0, 57) + "..."
            } else {
                $post.Title
            }
            "[$i] $title"
        }
        $postChoices += "⬅️  Back"

        $selection = Read-SpectreSelection -Title "[bold yellow]Select a post to view (Showing top $([Math]::Min($script:CurrentPosts.Count, 20)))[/]" -Choices $postChoices -Color "Cyan"

        if ($selection -notmatch "⬅️") {
            # Extract index from selection
            if ($selection -match '^\[(\d+)\]') {
                $index = [int]$matches[1]
                Show-PostDetail -Post $script:CurrentPosts[$index]
            }
        }
    }
    catch {
        Write-Log -Message "Error loading posts" -Level Error -ErrorRecord $_
        Write-SpectreHost "`n[red]Failed to load posts: $_[/]`n"
        Start-Sleep -Seconds 2
    }
}

function Show-PostDetail {
    <#
    .SYNOPSIS
        Shows detailed view of a post with comments
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Post
    )

    try {
        # Create post header panel
        $headerText = @"
[bold cyan]r/$($Post.Subreddit)[/] │ [green]u/$($Post.Author)[/]
⬆ [yellow]$($Post.Score)[/] │ 💬 [magenta]$($Post.NumComments)[/] comments
[dim]Posted: $($Post.Created)[/]
"@

        $titlePanel = Format-SpectrePanel -Data "[bold white]$($Post.Title)[/]" -Header "Post Details" -Border Rounded -Color Cyan
        Write-SpectreHost $titlePanel

        $headerPanel = Format-SpectrePanel -Data $headerText -Border Rounded -Color Green
        Write-SpectreHost $headerPanel

        # Show content if available
        if (-not [string]::IsNullOrWhiteSpace($Post.SelfText)) {
            $contentPanel = Format-SpectrePanel -Data $Post.SelfText -Header "Content" -Border Rounded -Color Yellow
            Write-SpectreHost $contentPanel
        } elseif ($Post.IsLink) {
            $linkPanel = Format-SpectrePanel -Data "[link]$($Post.LinkUrl)[/]" -Header "Link" -Border Rounded -Color Blue
            Write-SpectreHost $linkPanel
        }

        # Load and show comments
        Write-SpectreHost "`n[yellow]Loading comments...[/]`n"
        $comments = Get-RedditComments -Permalink $Post.Permalink -Limit 25

        if ($comments.Count -gt 0) {
            Write-SpectreHost "[bold cyan]Comments ($($comments.Count) loaded):[/]`n"
            Show-Comments -Comments $comments -MaxDepth 3
        } else {
            Write-SpectreHost "[yellow]No comments yet.[/]`n"
        }

        # Action menu
        $action = Read-SpectreSelection -Title "Actions" -Choices @(
            "🌐 Open in Browser",
            "⬅️  Back to Posts"
        ) -Color "Cyan"

        if ($action -match "🌐 Open") {
            $urlToOpen = if ($Post.IsLink) { $Post.LinkUrl } else { $Post.Url }
            Start-Process $urlToOpen
            Write-SpectreHost "[green]Opened in browser![/]`n"
            Start-Sleep -Seconds 1
        }
    }
    catch {
        Write-Log -Message "Error showing post detail" -Level Error -ErrorRecord $_
        Write-SpectreHost "`n[red]Failed to load post: $_[/]`n"
        Start-Sleep -Seconds 2
    }
}

function Show-Comments {
    <#
    .SYNOPSIS
        Recursively displays comments with proper indentation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Comments,

        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 3,

        [Parameter(Mandatory = $false)]
        [int]$CurrentDepth = 0
    )

    foreach ($comment in $Comments) {
        if ($CurrentDepth -ge $MaxDepth) {
            continue
        }

        $indent = "  " * $comment.Depth
        $opTag = if ($comment.IsOP) { " 🎤" } else { "" }
        $scoreColor = if ($comment.Score -ge 0) { "green" } else { "red" }

        # Author line
        Write-SpectreHost "$indent[bold $scoreColor]⬆ $($comment.Score)[/] [cyan]u/$($comment.Author)[/]$opTag"

        # Body
        $bodyLines = $comment.Body -split "`n"
        foreach ($line in $bodyLines) {
            Write-SpectreHost "$indent  [white]$line[/]"
        }
        Write-SpectreHost ""

        # Show replies
        if ($comment.Replies.Count -gt 0) {
            Show-Comments -Comments $comment.Replies -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1)
        }
    }
}

function Show-FavoritesMenu {
    <#
    .SYNOPSIS
        Shows the favorites management menu
    #>
    [CmdletBinding()]
    param()

    $back = $false
    while (-not $back) {
        try {
            # Reload favorites
            Get-Favorites | Out-Null

            $choices = @()
            if ($script:Favorites.Count -gt 0) {
                $choices += "📋 View/Select Favorite"
                $choices += "➕ Add New Favorite"
                $choices += "➖ Remove Favorite"
            } else {
                $choices += "➕ Add New Favorite"
            }
            $choices += "⬅️  Back to Main Menu"

            $choice = Read-SpectreSelection -Title "[bold yellow]Favorites Management[/]" -Choices $choices -Color "Cyan"

            switch -Wildcard ($choice) {
                "📋 View*" {
                    $favChoices = $script:Favorites | ForEach-Object { "r/$_" }
                    $favChoices += "⬅️  Back"
                    
                    $selected = Read-SpectreSelection -Title "Select a favorite subreddit" -Choices $favChoices -Color "Green"
                    
                    if ($selected -notmatch "⬅️") {
                        $script:CurrentSubreddit = $selected -replace '^r/', ''
                        Write-SpectreHost "[green]Switched to r/$($script:CurrentSubreddit)[/]`n"
                        Start-Sleep -Seconds 1
                        $back = $true
                    }
                }
                "➕ Add*" {
                    $newFav = Read-SpectreText -Prompt "Enter subreddit name to add"
                    if (-not [string]::IsNullOrWhiteSpace($newFav)) {
                        Add-Favorite -Subreddit $newFav
                        Write-SpectreHost "[green]Added r/$($newFav -replace '^r/', '') to favorites![/]`n"
                        Start-Sleep -Seconds 1
                    }
                }
                "➖ Remove*" {
                    if ($script:Favorites.Count -gt 0) {
                        $favChoices = $script:Favorites | ForEach-Object { "r/$_" }
                        $favChoices += "⬅️  Cancel"
                        
                        $selected = Read-SpectreSelection -Title "Select favorite to remove" -Choices $favChoices -Color "Red"
                        
                        if ($selected -notmatch "⬅️" -and $selected -notmatch "Cancel") {
                            $toRemove = $selected -replace '^r/', ''
                            Remove-Favorite -Subreddit $toRemove
                            Write-SpectreHost "[green]Removed r/$toRemove from favorites![/]`n"
                            Start-Sleep -Seconds 1
                        }
                    }
                }
                "⬅️  Back*" {
                    $back = $true
                }
            }
        }
        catch {
            Write-Log -Message "Error in favorites menu" -Level Error -ErrorRecord $_
            Write-SpectreHost "`n[red]Error: $_[/]`n"
            Start-Sleep -Seconds 2
        }
    }
}

function Show-SearchMenu {
    <#
    .SYNOPSIS
        Shows the search menu
    #>
    [CmdletBinding()]
    param()

    try {
        $query = Read-SpectreText -Prompt "Enter search query"
        
        if ([string]::IsNullOrWhiteSpace($query)) {
            return
        }

        $scope = Read-SpectreSelection -Title "Search Scope" -Choices @(
            "Current Subreddit (r/$($script:CurrentSubreddit))",
            "All of Reddit"
        ) -Color "Cyan"

        Write-SpectreHost "`n[yellow]Searching...[/]`n"

        if ($scope -match "Current") {
            $results = Search-Reddit -Query $query -Subreddit $script:CurrentSubreddit
        } else {
            $results = Search-Reddit -Query $query
        }

        if ($results.Count -eq 0) {
            Write-SpectreHost "[yellow]No results found.[/]`n"
            Start-Sleep -Seconds 2
            return
        }

        # Show results in table
        $table = Format-SpectreTable -Data $results -Property @(
            @{Label = "Score"; Expression = { "⬆ $($_.Score)" }},
            @{Label = "Sub"; Expression = { "r/$($_.Subreddit)" }},
            @{Label = "Title"; Expression = { 
                if ($_.Title.Length -gt 50) {
                    $_.Title.Substring(0, 47) + "..."
                } else {
                    $_.Title
                }
            }}
        ) -Border Rounded -Color Cyan

        Write-SpectreHost $table

        # Create menu choices from results
        $resultChoices = for ($i = 0; $i -lt [Math]::Min($results.Count, 15); $i++) {
            $result = $results[$i]
            $title = if ($result.Title.Length -gt 50) {
                $result.Title.Substring(0, 47) + "..."
            } else {
                $result.Title
            }
            "[$i] r/$($result.Subreddit) - $title"
        }
        $resultChoices += "⬅️  Back"

        $selection = Read-SpectreSelection -Title "[bold yellow]Search Results (Showing top $([Math]::Min($results.Count, 15)))[/]" -Choices $resultChoices -Color "Cyan"

        if ($selection -notmatch "⬅️") {
            if ($selection -match '^\[(\d+)\]') {
                $index = [int]$matches[1]
                Show-PostDetail -Post $results[$index]
            }
        }
    }
    catch {
        Write-Log -Message "Error in search" -Level Error -ErrorRecord $_
        Write-SpectreHost "`n[red]Search failed: $_[/]`n"
        Start-Sleep -Seconds 2
    }
}

function Show-SettingsMenu {
    <#
    .SYNOPSIS
        Shows the settings menu
    #>
    [CmdletBinding()]
    param()

    $back = $false
    while (-not $back) {
        try {
            $choices = @(
                "📊 View Logs",
                "🗑️  Clear Logs",
                "🔧 Set Log Level (Current: $script:LogLevel)",
                "⬅️  Back to Main Menu"
            )

            $choice = Read-SpectreSelection -Title "[bold yellow]Settings[/]" -Choices $choices -Color "Cyan"

            switch -Wildcard ($choice) {
                "📊 View Logs*" {
                    $logLines = Get-PSRedditTUILog -Tail 50
                    if ($logLines) {
                        $logPanel = Format-SpectrePanel -Data ($logLines -join "`n") -Header "Recent Log Entries (Last 50)" -Border Rounded -Color Yellow
                        Write-SpectreHost $logPanel
                        Read-SpectrePause -Message "Press any key to continue"
                    } else {
                        Write-SpectreHost "[yellow]No log entries found.[/]`n"
                        Start-Sleep -Seconds 2
                    }
                }
                "🗑️  Clear Logs*" {
                    Clear-PSRedditTUILog
                    Write-SpectreHost "[green]Logs cleared![/]`n"
                    Start-Sleep -Seconds 1
                }
                "🔧 Set Log Level*" {
                    $level = Read-SpectreSelection -Title "Select Log Level" -Choices @("Debug", "Info", "Warning", "Error") -Color "Green"
                    Set-PSRedditTUILogLevel -Level $level
                    Write-SpectreHost "[green]Log level set to: $level[/]`n"
                    Start-Sleep -Seconds 1
                }
                "⬅️  Back*" {
                    $back = $true
                }
            }
        }
        catch {
            Write-Log -Message "Error in settings menu" -Level Error -ErrorRecord $_
            Write-SpectreHost "`n[red]Error: $_[/]`n"
            Start-Sleep -Seconds 2
        }
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Get-RedditData',
    'Get-RedditPosts',
    'Get-RedditComments',
    'Search-Reddit',
    'Get-Favorites',
    'Add-Favorite',
    'Remove-Favorite',
    'Show-RedditTUI',
    'Get-PSRedditTUILog',
    'Clear-PSRedditTUILog',
    'Set-PSRedditTUILogLevel'
)
