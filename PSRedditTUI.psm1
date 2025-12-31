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

    # Initialize state - use local variables instead of script scope
    $currentSubreddit = $InitialSubreddit
    $currentSort = "hot"
    $currentTime = "day"
    $currentPosts = @()
    $running = $true

    Write-SpectreHost "`n[bold cyan]PSRedditTUI - Reddit Terminal Browser[/]`n" -NoNewline

    # Main loop
    while ($running) {
        try {
            # Show main menu
            $mainChoice = Read-SpectreSelection -Title "[bold yellow]Main Menu[/]" -Choices @(
                "📖 Browse Subreddit: r/$currentSubreddit",
                "⭐ Manage Favorites",
                "🔍 Search Reddit",
                "⚙️  Settings",
                "❌ Exit"
            ) -Color "Cyan"

            switch -Wildcard ($mainChoice) {
                "📖 Browse*" {
                    # Browse subreddit inline
                    $browseBack = $false
                    while (-not $browseBack) {
                        $browseChoice = Read-SpectreSelection -Title "[bold yellow]Browse r/$currentSubreddit[/]" -Choices @(
                            "📋 View Posts (Sort: $currentSort$(if ($currentSort -eq 'top') { "/$currentTime" }))",
                            "🔄 Change Subreddit",
                            "📊 Change Sort",
                            "⬅️  Back to Main Menu"
                        ) -Color "Cyan"

                        switch -Wildcard ($browseChoice) {
                            "📋 View Posts*" {
                                # Load and display posts inline
                                Write-SpectreHost "`n[yellow]Loading posts from r/$currentSubreddit...[/]`n"
                                $currentPosts = Get-RedditPosts -Subreddit $currentSubreddit -Sort $currentSort -Time $currentTime

                                if ($currentPosts.Count -eq 0) {
                                    Write-SpectreHost "[yellow]No posts found.[/]`n"
                                } else {
                                    # Create simple menu without duplicate table display
                                    $postChoices = for ($i = 0; $i -lt [Math]::Min($currentPosts.Count, 25); $i++) {
                                        $post = $currentPosts[$i]
                                        $title = if ($post.Title.Length -gt 70) { $post.Title.Substring(0, 67) + "..." } else { $post.Title }
                                        "[$i] ⬆$($post.Score) 💬$($post.NumComments) │ $title"
                                    }
                                    $postChoices += "⬅️  Back"

                                    $postSelection = Read-SpectreSelection -Title "[bold yellow]Select a post (Showing $([Math]::Min($currentPosts.Count, 25)) of $($currentPosts.Count))[/]" -Choices $postChoices -Color "Cyan"

                                    if ($postSelection -match '^\[(\d+)\]') {
                                        $postIndex = [int]$matches[1]
                                        $selectedPost = $currentPosts[$postIndex]

                                        # Display post detail inline
                                        $headerText = @"
[bold cyan]r/$($selectedPost.Subreddit)[/] │ [green]u/$($selectedPost.Author)[/]
⬆ [yellow]$($selectedPost.Score)[/] │ 💬 [magenta]$($selectedPost.NumComments)[/] comments │ [dim]$($selectedPost.Created)[/]
"@
                                        $titlePanel = Format-SpectrePanel -Data "[bold white]$($selectedPost.Title)[/]" -Header "Post Details" -Border Rounded -Color Cyan
                                        Write-SpectreHost $titlePanel
                                        $headerPanel = Format-SpectrePanel -Data $headerText -Border Rounded -Color Green
                                        Write-SpectreHost $headerPanel

                                        if (-not [string]::IsNullOrWhiteSpace($selectedPost.SelfText)) {
                                            $contentPanel = Format-SpectrePanel -Data $selectedPost.SelfText -Header "Content" -Border Rounded -Color Yellow
                                            Write-SpectreHost $contentPanel
                                        } elseif ($selectedPost.IsLink) {
                                            $linkPanel = Format-SpectrePanel -Data "[link]$($selectedPost.LinkUrl)[/]" -Header "Link" -Border Rounded -Color Blue
                                            Write-SpectreHost $linkPanel
                                        }

                                        # Load comments
                                        Write-SpectreHost "`n[yellow]Loading comments...[/]`n"
                                        $comments = Get-RedditComments -Permalink $selectedPost.Permalink -Limit 25

                                        if ($comments.Count -gt 0) {
                                            Write-SpectreHost "[bold cyan]Comments ($($comments.Count) loaded):[/]`n"
                                            # Display comments inline with recursion
                                            function Show-CommentThread {
                                                param($Comments, $MaxDepth = 3, $CurrentDepth = 0)
                                                foreach ($comment in $Comments) {
                                                    if ($CurrentDepth -ge $MaxDepth) { continue }
                                                    $indent = "  " * $CurrentDepth
                                                    $opTag = if ($comment.IsOP) { " 🎤" } else { "" }
                                                    $scoreColor = if ($comment.Score -ge 0) { "green" } else { "red" }
                                                    Write-SpectreHost "$indent[bold $scoreColor]⬆ $($comment.Score)[/] [cyan]u/$($comment.Author)[/]$opTag"
                                                    $bodyLines = $comment.Body -split "`n"
                                                    foreach ($line in $bodyLines) {
                                                        Write-SpectreHost "$indent  [white]$line[/]"
                                                    }
                                                    Write-SpectreHost ""
                                                    if ($comment.Replies.Count -gt 0) {
                                                        Show-CommentThread -Comments $comment.Replies -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1)
                                                    }
                                                }
                                            }
                                            Show-CommentThread -Comments $comments
                                        } else {
                                            Write-SpectreHost "[yellow]No comments yet.[/]`n"
                                        }

                                        # Action menu
                                        $action = Read-SpectreSelection -Title "Actions" -Choices @("🌐 Open in Browser", "⬅️  Back to Posts") -Color "Cyan"
                                        if ($action -match "🌐 Open") {
                                            $urlToOpen = if ($selectedPost.IsLink) { $selectedPost.LinkUrl } else { $selectedPost.Url }
                                            Start-Process $urlToOpen
                                            Write-SpectreHost "[green]Opened in browser![/]`n"
                                        }
                                    }
                                }
                            }
                            "🔄 Change Subreddit*" {
                                $newSub = Read-SpectreText -Prompt "Enter subreddit name" -DefaultAnswer $currentSubreddit
                                if (-not [string]::IsNullOrWhiteSpace($newSub)) {
                                    $currentSubreddit = $newSub -replace '^r/', ''
                                    Write-Log -Message "Changed subreddit to: $currentSubreddit" -Level Info
                                }
                            }
                            "📊 Change Sort*" {
                                $currentSort = Read-SpectreSelection -Title "Select Sort Order" -Choices @("hot", "new", "top", "rising") -Color "Green"
                                if ($currentSort -eq "top") {
                                    $currentTime = Read-SpectreSelection -Title "Select Time Filter" -Choices @("hour", "day", "week", "month", "year", "all") -Color "Green"
                                }
                                Write-Log -Message "Changed sort to: $currentSort$(if ($currentSort -eq 'top') { "/$currentTime" })" -Level Info
                            }
                            "⬅️  Back*" {
                                $browseBack = $true
                            }
                        }
                    }
                }
                "⭐ Manage*" {
                    # Manage favorites inline
                    $favBack = $false
                    while (-not $favBack) {
                        Get-Favorites | Out-Null
                        $favChoices = @()
                        if ($script:Favorites.Count -gt 0) {
                            $favChoices += "📋 View/Select Favorite"
                            $favChoices += "➕ Add New Favorite"
                            $favChoices += "➖ Remove Favorite"
                        } else {
                            $favChoices += "➕ Add New Favorite"
                        }
                        $favChoices += "⬅️  Back to Main Menu"

                        $favChoice = Read-SpectreSelection -Title "[bold yellow]Favorites Management[/]" -Choices $favChoices -Color "Cyan"

                        switch -Wildcard ($favChoice) {
                            "📋 View*" {
                                $favList = $script:Favorites | ForEach-Object { "r/$_" }
                                $favList += "⬅️  Back"
                                $selected = Read-SpectreSelection -Title "Select a favorite subreddit" -Choices $favList -Color "Green"
                                if ($selected -notmatch "⬅️") {
                                    $currentSubreddit = $selected -replace '^r/', ''
                                    Write-SpectreHost "[green]Switched to r/$currentSubreddit[/]`n"
                                    $favBack = $true
                                }
                            }
                            "➕ Add*" {
                                $newFav = Read-SpectreText -Prompt "Enter subreddit name to add"
                                if (-not [string]::IsNullOrWhiteSpace($newFav)) {
                                    Add-Favorite -Subreddit $newFav
                                    Write-SpectreHost "[green]Added r/$($newFav -replace '^r/', '') to favorites![/]`n"
                                }
                            }
                            "➖ Remove*" {
                                if ($script:Favorites.Count -gt 0) {
                                    $favList = $script:Favorites | ForEach-Object { "r/$_" }
                                    $favList += "⬅️  Cancel"
                                    $selected = Read-SpectreSelection -Title "Select favorite to remove" -Choices $favList -Color "Red"
                                    if ($selected -notmatch "⬅️" -and $selected -notmatch "Cancel") {
                                        $toRemove = $selected -replace '^r/', ''
                                        Remove-Favorite -Subreddit $toRemove
                                        Write-SpectreHost "[green]Removed r/$toRemove from favorites![/]`n"
                                    }
                                }
                            }
                            "⬅️  Back*" {
                                $favBack = $true
                            }
                        }
                    }
                }
                "🔍 Search*" {
                    # Search inline
                    $query = Read-SpectreText -Prompt "Enter search query"
                    if (-not [string]::IsNullOrWhiteSpace($query)) {
                        $scope = Read-SpectreSelection -Title "Search Scope" -Choices @(
                            "Current Subreddit (r/$currentSubreddit)",
                            "All of Reddit"
                        ) -Color "Cyan"

                        Write-SpectreHost "`n[yellow]Searching...[/]`n"
                        $results = if ($scope -match "Current") {
                            Search-Reddit -Query $query -Subreddit $currentSubreddit
                        } else {
                            Search-Reddit -Query $query
                        }

                        if ($results.Count -eq 0) {
                            Write-SpectreHost "[yellow]No results found.[/]`n"
                        } else {
                            # Display search results using same post display logic
                            $resultChoices = for ($i = 0; $i -lt [Math]::Min($results.Count, 25); $i++) {
                                $result = $results[$i]
                                $title = if ($result.Title.Length -gt 60) { $result.Title.Substring(0, 57) + "..." } else { $result.Title }
                                "[$i] ⬆$($result.Score) r/$($result.Subreddit) │ $title"
                            }
                            $resultChoices += "⬅️  Back"

                            $resultSelection = Read-SpectreSelection -Title "[bold yellow]Search Results (Showing $([Math]::Min($results.Count, 25)) of $($results.Count))[/]" -Choices $resultChoices -Color "Cyan"

                            if ($resultSelection -match '^\[(\d+)\]') {
                                $resultIndex = [int]$matches[1]
                                $selectedPost = $results[$resultIndex]

                                # Reuse post display logic (same as browse section)
                                $headerText = @"
[bold cyan]r/$($selectedPost.Subreddit)[/] │ [green]u/$($selectedPost.Author)[/]
⬆ [yellow]$($selectedPost.Score)[/] │ 💬 [magenta]$($selectedPost.NumComments)[/] comments │ [dim]$($selectedPost.Created)[/]
"@
                                $titlePanel = Format-SpectrePanel -Data "[bold white]$($selectedPost.Title)[/]" -Header "Post Details" -Border Rounded -Color Cyan
                                Write-SpectreHost $titlePanel
                                $headerPanel = Format-SpectrePanel -Data $headerText -Border Rounded -Color Green
                                Write-SpectreHost $headerPanel

                                if (-not [string]::IsNullOrWhiteSpace($selectedPost.SelfText)) {
                                    $contentPanel = Format-SpectrePanel -Data $selectedPost.SelfText -Header "Content" -Border Rounded -Color Yellow
                                    Write-SpectreHost $contentPanel
                                } elseif ($selectedPost.IsLink) {
                                    $linkPanel = Format-SpectrePanel -Data "[link]$($selectedPost.LinkUrl)[/]" -Header "Link" -Border Rounded -Color Blue
                                    Write-SpectreHost $linkPanel
                                }

                                Write-SpectreHost "`n[yellow]Loading comments...[/]`n"
                                $comments = Get-RedditComments -Permalink $selectedPost.Permalink -Limit 25

                                if ($comments.Count -gt 0) {
                                    Write-SpectreHost "[bold cyan]Comments ($($comments.Count) loaded):[/]`n"
                                    function Show-CommentThread {
                                        param($Comments, $MaxDepth = 3, $CurrentDepth = 0)
                                        foreach ($comment in $Comments) {
                                            if ($CurrentDepth -ge $MaxDepth) { continue }
                                            $indent = "  " * $CurrentDepth
                                            $opTag = if ($comment.IsOP) { " 🎤" } else { "" }
                                            $scoreColor = if ($comment.Score -ge 0) { "green" } else { "red" }
                                            Write-SpectreHost "$indent[bold $scoreColor]⬆ $($comment.Score)[/] [cyan]u/$($comment.Author)[/]$opTag"
                                            $bodyLines = $comment.Body -split "`n"
                                            foreach ($line in $bodyLines) {
                                                Write-SpectreHost "$indent  [white]$line[/]"
                                            }
                                            Write-SpectreHost ""
                                            if ($comment.Replies.Count -gt 0) {
                                                Show-CommentThread -Comments $comment.Replies -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1)
                                            }
                                        }
                                    }
                                    Show-CommentThread -Comments $comments
                                } else {
                                    Write-SpectreHost "[yellow]No comments yet.[/]`n"
                                }

                                $action = Read-SpectreSelection -Title "Actions" -Choices @("🌐 Open in Browser", "⬅️  Back to Results") -Color "Cyan"
                                if ($action -match "🌐 Open") {
                                    $urlToOpen = if ($selectedPost.IsLink) { $selectedPost.LinkUrl } else { $selectedPost.Url }
                                    Start-Process $urlToOpen
                                    Write-SpectreHost "[green]Opened in browser![/]`n"
                                }
                            }
                        }
                    }
                }
                "⚙️  Settings*" {
                    # Settings inline
                    $settingsBack = $false
                    while (-not $settingsBack) {
                        $settingsChoice = Read-SpectreSelection -Title "[bold yellow]Settings[/]" -Choices @(
                            "📊 View Logs",
                            "🗑️  Clear Logs",
                            "🔧 Set Log Level (Current: $script:LogLevel)",
                            "⬅️  Back to Main Menu"
                        ) -Color "Cyan"

                        switch -Wildcard ($settingsChoice) {
                            "📊 View Logs*" {
                                $logLines = Get-PSRedditTUILog -Tail 50
                                if ($logLines) {
                                    $logPanel = Format-SpectrePanel -Data ($logLines -join "`n") -Header "Recent Log Entries (Last 50)" -Border Rounded -Color Yellow
                                    Write-SpectreHost $logPanel
                                    Read-SpectrePause -Message "Press any key to continue"
                                } else {
                                    Write-SpectreHost "[yellow]No log entries found.[/]`n"
                                }
                            }
                            "🗑️  Clear Logs*" {
                                Clear-PSRedditTUILog
                                Write-SpectreHost "[green]Logs cleared![/]`n"
                            }
                            "🔧 Set Log Level*" {
                                $level = Read-SpectreSelection -Title "Select Log Level" -Choices @("Debug", "Info", "Warning", "Error") -Color "Green"
                                Set-PSRedditTUILogLevel -Level $level
                                Write-SpectreHost "[green]Log level set to: $level[/]`n"
                            }
                            "⬅️  Back*" {
                                $settingsBack = $true
                            }
                        }
                    }
                }
                "❌ Exit*" {
                    $running = $false
                    Write-SpectreHost "`n[green]Thanks for using PSRedditTUI! 👋[/]`n"
                }
            }
        }
        catch {
            Write-Log -Message "Error in main menu loop" -Level Error -ErrorRecord $_
            Write-SpectreHost "`n[red]Error: $_[/]`n"
        }
    }

    Write-Log -Message "Show-RedditTUI exiting normally" -Level Info
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
