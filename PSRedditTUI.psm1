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

function Write-ErrorLog {
    <#
    .SYNOPSIS
        Convenience function for logging errors with full context
    .PARAMETER Message
        The error message
    .PARAMETER ErrorRecord
        The ErrorRecord from catch block ($_)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        $ErrorRecord
    )

    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        Write-Log -Message $Message -Level Error -Exception $ErrorRecord.Exception -ErrorRecord $ErrorRecord
    }
    elseif ($ErrorRecord -is [System.Exception]) {
        Write-Log -Message $Message -Level Error -Exception $ErrorRecord
    }
    else {
        Write-Log -Message "$Message - $ErrorRecord" -Level Error
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

Write-Log -Message "PSRedditTUI module loading..." -Level Info
Write-Log -Message "PowerShell version: $($PSVersionTable.PSVersion)" -Level Debug
Write-Log -Message "OS: $($PSVersionTable.OS)" -Level Debug

# Auto-load Terminal.Gui and NStack if installed via Install-PSRedditTUITerminalGui
& {
    $packageDir = Join-Path $HOME ".psreddittui-packages"
    $terminalGuiDll = Join-Path $packageDir "Terminal.Gui/lib/net8.0/Terminal.Gui.dll"
    $nstackDll = Join-Path $packageDir "NStack.Core/lib/netstandard2.0/NStack.dll"

    Write-Log -Message "Checking for Terminal.Gui at: $terminalGuiDll" -Level Debug

    if ((Test-Path $nstackDll) -and (Test-Path $terminalGuiDll)) {
        try {
            if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'NStack' })) {
                Add-Type -Path $nstackDll
                Write-Log -Message "Loaded NStack from: $nstackDll" -Level Debug
            }
            if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Terminal.Gui' })) {
                Add-Type -Path $terminalGuiDll
                Write-Log -Message "Loaded Terminal.Gui from: $terminalGuiDll" -Level Info
            }
        }
        catch {
            Write-ErrorLog -Message "Failed to auto-load Terminal.Gui" -ErrorRecord $_
            Write-Warning "Failed to auto-load Terminal.Gui: $_"
        }
    } else {
        Write-Log -Message "Terminal.Gui not found at expected path" -Level Warning
    }
}

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
            Write-ErrorLog -Message "Failed to parse JSON response from: $Url" -ErrorRecord $_
            Write-Log -Message "Invalid JSON content: $preview" -Level Error
            Write-Error "Response is not valid JSON: $_"
            return $null
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to fetch Reddit data from: $Url" -ErrorRecord $_
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
        [ValidatePattern('^[a-zA-Z0-9_]+$')]
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
        $moduleVersion = "1.0.0"
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
        Write-ErrorLog -Message "Search failed for query: '$Query' (subreddit: $Subreddit)" -ErrorRecord $_
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
            Write-ErrorLog -Message "Failed to load favorites from: $script:FavoritesFile" -ErrorRecord $_
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
            Write-ErrorLog -Message "Failed to save default favorites" -ErrorRecord $_
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
        Write-ErrorLog -Message "Failed to save favorites to: $script:FavoritesFile" -ErrorRecord $_
        Write-Error "Failed to save favorites: $_"
    }
}

function Add-Favorite {
    <#
    .SYNOPSIS
        Adds a subreddit to favorites
    .PARAMETER Subreddit
        The subreddit name to add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subreddit
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
        Write-Information "Added '$normalizedSubreddit' to favorites" -InformationAction Continue
    }
    else {
        Write-Log -Message "'$normalizedSubreddit' already exists in favorites" -Level Debug
        Write-Information "'$normalizedSubreddit' is already in favorites" -InformationAction Continue
    }
}

function Remove-Favorite {
    <#
    .SYNOPSIS
        Removes a subreddit from favorites
    .PARAMETER Subreddit
        The subreddit name to remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subreddit
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
        Write-Information "Removed '$normalizedSubreddit' from favorites" -InformationAction Continue
    }
    else {
        Write-Log -Message "'$normalizedSubreddit' not found in favorites" -Level Debug
        Write-Information "'$normalizedSubreddit' is not in favorites" -InformationAction Continue
    }
}

#endregion

#region Helper Functions

function Open-UrlInBrowser {
    <#
    .SYNOPSIS
        Opens a URL in the default browser
    .PARAMETER Url
        The URL to open
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    Write-Log -Message "Opening URL in browser: $Url" -Level Info

    try {
        if ($IsWindows -or $env:OS -match 'Windows') {
            Start-Process $Url
        } elseif ($IsMacOS) {
            Start-Process "open" -ArgumentList $Url
        } else {
            Start-Process "xdg-open" -ArgumentList $Url
        }
        return $true
    }
    catch {
        Write-ErrorLog -Message "Failed to open URL in browser: $Url" -ErrorRecord $_
        return $false
    }
}

#endregion

#region Terminal UI

function Show-RedditTUI {
    <#
    .SYNOPSIS
        Launches the Terminal UI for browsing Reddit
    .DESCRIPTION
        Opens an interactive Terminal UI using Terminal.Gui for browsing Reddit with a favorites sidebar
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

    # Check if Terminal.Gui is available
    try {
        $null = [Terminal.Gui.Application]
        Write-Log -Message "Terminal.Gui is available" -Level Debug
    }
    catch {
        Write-ErrorLog -Message "Terminal.Gui is not available - run Install-PSRedditTUITerminalGui" -ErrorRecord $_
        Write-Error "Terminal.Gui is not available. Run 'Install-PSRedditTUITerminalGui' to install the dependency, or manually install the Terminal.Gui .NET assembly."
        return
    }

    # Load favorites
    Get-Favorites | Out-Null

    # Initialize Terminal.Gui
    Write-Log -Message "Initializing Terminal.Gui Application" -Level Debug
    [Terminal.Gui.Application]::Init()

    try {
        # Create main window
        $top = [Terminal.Gui.Application]::Top
        
        # Create main container
        $win = [Terminal.Gui.Window]::new("PSRedditTUI - Reddit Terminal Browser")
        $win.X = 0
        $win.Y = 0
        $win.Width  = [Terminal.Gui.Dim]::Fill()
        $win.Height = [Terminal.Gui.Dim]::Fill()
        
        
        # Create menu bar
        $menu = [Terminal.Gui.MenuBar]::new(@(
            [Terminal.Gui.MenuBarItem]::new("_File", @(
                [Terminal.Gui.MenuItem]::new("_Quit", "Exit application", { [Terminal.Gui.Application]::RequestStop() })
            )),
            [Terminal.Gui.MenuBarItem]::new("_Help", @(
                [Terminal.Gui.MenuItem]::new("_About", "About PSRedditTUI", {
                    [Terminal.Gui.MessageBox]::Query("About", "PSRedditTUI v1.0`nA PowerShell Reddit Terminal Browser`nPress ESC to close", @("OK"))
                })
            ))
        ))
        $top.Add($menu)
        
        # Create favorites sidebar (left side)
        $favoritesFrame = [Terminal.Gui.FrameView]::new()
        $favoritesFrame.Title = "Favorites"
        $favoritesFrame.X = 0
        $favoritesFrame.Y = 1
        $favoritesFrame.Width = 25
        $favoritesFrame.Height = [Terminal.Gui.Dim]::Fill()
        
        $favoritesList = [Terminal.Gui.ListView]::new()
        $favoritesList.X = 0
        $favoritesList.Y = 0
        $favoritesList.Width = [Terminal.Gui.Dim]::Fill()
        $favoritesList.Height = [Terminal.Gui.Dim]::Fill(2)
        
        # Populate favorites list
        $favoritesSource = [System.Collections.Generic.List[string]]::new()
        foreach ($fav in $script:Favorites) {
            $favoritesSource.Add("r/$fav")
        }
        $favoritesList.SetSource($favoritesSource)
        
        $favoritesFrame.Add($favoritesList)
        
        # Add favorite buttons
        $addFavBtn = [Terminal.Gui.Button]::new()
        $addFavBtn.Text = "Add"
        $addFavBtn.X = 0
        $addFavBtn.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
        
        $removeFavBtn = [Terminal.Gui.Button]::new()
        $removeFavBtn.Text = "Remove"
        $removeFavBtn.X = [Terminal.Gui.Pos]::Right($addFavBtn) + 1
        $removeFavBtn.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
        
        $favoritesFrame.Add($addFavBtn)
        $favoritesFrame.Add($removeFavBtn)
        
        # Create main content area (right side)
        $contentFrame = [Terminal.Gui.FrameView]::new()
        $contentFrame.Title  = "r/$InitialSubreddit"
        $contentFrame.X      = 25
        $contentFrame.Y      = 1
        $contentFrame.Width  = [Terminal.Gui.Dim]::Fill()
        $contentFrame.Height = [Terminal.Gui.Dim]::Fill()
        
        # Subreddit input (Row 0)
        $subredditLabel = [Terminal.Gui.Label]::new()
        $subredditLabel.Text = "Subreddit:"
        $subredditLabel.X = 0
        $subredditLabel.Y = 0

        $subredditInput = [Terminal.Gui.TextField]::new()
        $subredditInput.Text = $InitialSubreddit
        $subredditInput.X = [Terminal.Gui.Pos]::Right($subredditLabel) + 1
        $subredditInput.Y = 0
        $subredditInput.Width = 20

        $loadBtn = [Terminal.Gui.Button]::new()
        $loadBtn.Text = "Load"
        $loadBtn.X = [Terminal.Gui.Pos]::Right($subredditInput) + 1
        $loadBtn.Y = 0

        $contentFrame.Add($subredditLabel)
        $contentFrame.Add($subredditInput)
        $contentFrame.Add($loadBtn)

        # Sort and Time Filter (Row 1)
        $sortLabel = [Terminal.Gui.Label]::new()
        $sortLabel.Text = "Sort:"
        $sortLabel.X = 0
        $sortLabel.Y = 1

        # Sort options
        $sortOptions = [System.Collections.Generic.List[string]]::new()
        @("hot", "new", "top", "rising") | ForEach-Object { $sortOptions.Add($_) }

        $sortCombo = [Terminal.Gui.ComboBox]::new()
        $sortCombo.X = [Terminal.Gui.Pos]::Right($sortLabel) + 1
        $sortCombo.Y = 1
        $sortCombo.Width = 10
        $sortCombo.Height = 5
        $sortCombo.SetSource($sortOptions)
        $sortCombo.SelectedItem = 0  # Default to "hot"

        # Time filter label
        $timeLabel = [Terminal.Gui.Label]::new()
        $timeLabel.Text = "Time:"
        $timeLabel.X = [Terminal.Gui.Pos]::Right($sortCombo) + 2
        $timeLabel.Y = 1
        $timeLabel.Visible = $false  # Only visible when sort=top

        # Time filter options
        $timeOptions = [System.Collections.Generic.List[string]]::new()
        @("day", "week", "month", "year", "all") | ForEach-Object { $timeOptions.Add($_) }

        $timeCombo = [Terminal.Gui.ComboBox]::new()
        $timeCombo.X = [Terminal.Gui.Pos]::Right($timeLabel) + 1
        $timeCombo.Y = 1
        $timeCombo.Width = 10
        $timeCombo.Height = 5
        $timeCombo.SetSource($timeOptions)
        $timeCombo.SelectedItem = 0  # Default to "day"
        $timeCombo.Visible = $false  # Only visible when sort=top

        # Track current sort/time
        $script:CurrentSort = "hot"
        $script:CurrentTime = "day"

        # Sort combo selection changed
        $sortCombo.add_SelectedItemChanged({
            Write-Log -Message "TUI: EVENT - Sort combo SelectedItemChanged triggered" -Level Debug
            try {
                if ($null -eq $sortCombo) {
                    Write-Log -Message "TUI: EVENT - sortCombo is null, returning" -Level Warning
                    return
                }
                $selectedIdx = $sortCombo.SelectedItem
                Write-Log -Message "TUI: EVENT - Sort selected index: $selectedIdx" -Level Debug
                if ($selectedIdx -ge 0 -and $selectedIdx -lt $sortOptions.Count) {
                    $script:CurrentSort = $sortOptions[$selectedIdx]
                    Write-Log -Message "TUI: Sort changed to: $($script:CurrentSort)" -Level Debug

                    # Show/hide time filter based on sort type
                    $showTime = ($script:CurrentSort -eq "top")
                    Write-Log -Message "TUI: EVENT - Setting time filter visibility: $showTime" -Level Debug
                    if ($null -ne $timeLabel) {
                        $timeLabel.Visible = $showTime
                        Write-Log -Message "TUI: EVENT - timeLabel.Visible set to $showTime" -Level Debug
                    } else {
                        Write-Log -Message "TUI: EVENT - timeLabel is null" -Level Warning
                    }
                    if ($null -ne $timeCombo) {
                        $timeCombo.Visible = $showTime
                        Write-Log -Message "TUI: EVENT - timeCombo.Visible set to $showTime" -Level Debug
                    } else {
                        Write-Log -Message "TUI: EVENT - timeCombo is null" -Level Warning
                    }
                }
                Write-Log -Message "TUI: EVENT - Sort combo handler completed successfully" -Level Debug
            }
            catch {
                Write-ErrorLog -Message "TUI: EVENT - Failed in sort combo handler" -ErrorRecord $_
            }
        })

        # Time combo selection changed
        $timeCombo.add_SelectedItemChanged({
            try {
                $selectedIdx = $timeCombo.SelectedItem
                if ($selectedIdx -ge 0 -and $selectedIdx -lt $timeOptions.Count) {
                    $script:CurrentTime = $timeOptions[$selectedIdx]
                    Write-Log -Message "TUI: Time filter changed to: $($script:CurrentTime)" -Level Debug
                }
            }
            catch {
                Write-ErrorLog -Message "TUI: Failed to change time filter" -ErrorRecord $_
            }
        })

        $contentFrame.Add($sortLabel)
        $contentFrame.Add($sortCombo)
        $contentFrame.Add($timeLabel)
        $contentFrame.Add($timeCombo)

        # Search row (Row 2)
        $searchLabel = [Terminal.Gui.Label]::new()
        $searchLabel.Text = "Search:"
        $searchLabel.X = 0
        $searchLabel.Y = 2

        $searchInput = [Terminal.Gui.TextField]::new()
        $searchInput.X = [Terminal.Gui.Pos]::Right($searchLabel) + 1
        $searchInput.Y = 2
        $searchInput.Width = 30

        $searchBtn = [Terminal.Gui.Button]::new()
        $searchBtn.Text = "Search"
        $searchBtn.X = [Terminal.Gui.Pos]::Right($searchInput) + 1
        $searchBtn.Y = 2

        $searchGlobalCheck = [Terminal.Gui.CheckBox]::new()
        $searchGlobalCheck.Text = "All Reddit"
        $searchGlobalCheck.X = [Terminal.Gui.Pos]::Right($searchBtn) + 1
        $searchGlobalCheck.Y = 2

        $contentFrame.Add($searchLabel)
        $contentFrame.Add($searchInput)
        $contentFrame.Add($searchBtn)
        $contentFrame.Add($searchGlobalCheck)

        # Posts list view (moved to Y=4 for search row)
        $postsListView = [Terminal.Gui.ListView]::new()
        $postsListView.X = 0
        $postsListView.Y = 4
        $postsListView.Width = [Terminal.Gui.Dim]::Fill()
        $postsListView.Height = [Terminal.Gui.Dim]::Fill()

        $contentFrame.Add($postsListView)

        # Store current posts for click handling
        $script:CurrentPosts = @()
        $script:IsSearchResults = $false

        # Function to format comments with indentation
        $formatComments = {
            param($comments, $maxDepth = 3)

            $lines = [System.Collections.Generic.List[string]]::new()

            $processComment = {
                param($comment, $currentDepth)

                if ($currentDepth -gt $maxDepth) { return }

                $indent = "  " * $comment.Depth
                $opTag = if ($comment.IsOP) { " 🎤" } else { "" }
                $scoreStr = if ($comment.Score -ge 0) { "+$($comment.Score)" } else { "$($comment.Score)" }

                # Author line
                $lines.Add("$indent⬆$scoreStr 👤 u/$($comment.Author)$opTag")

                # Body - wrap long lines
                $bodyLines = $comment.Body -split "`n"
                foreach ($bodyLine in $bodyLines) {
                    # Wrap at ~70 chars accounting for indent
                    $maxLen = 70 - ($comment.Depth * 2)
                    if ($maxLen -lt 30) { $maxLen = 30 }

                    if ($bodyLine.Length -gt $maxLen) {
                        $words = $bodyLine -split ' '
                        $currentLine = "$indent  "
                        foreach ($word in $words) {
                            if (($currentLine.Length + $word.Length + 1) -gt ($maxLen + $indent.Length + 2)) {
                                $lines.Add($currentLine.TrimEnd())
                                $currentLine = "$indent  $word "
                            } else {
                                $currentLine += "$word "
                            }
                        }
                        if ($currentLine.Trim().Length -gt 0) {
                            $lines.Add($currentLine.TrimEnd())
                        }
                    } else {
                        $lines.Add("$indent  $bodyLine")
                    }
                }
                $lines.Add("")  # Blank line after comment

                # Process replies
                foreach ($reply in $comment.Replies) {
                    & $processComment $reply ($currentDepth + 1)
                }
            }

            foreach ($comment in $comments) {
                & $processComment $comment 0
            }

            return $lines
        }

        # Function to show post details dialog
        $showPostDetail = {
            param($post)

            Write-Log -Message "TUI: Opening post detail for: $($post.Title)" -Level Info

            # Create dialog
            $dialog = [Terminal.Gui.Dialog]::new()
            $dialog.Title = "Post Details (ESC to close)"
            $dialog.Width = [Terminal.Gui.Dim]::Percent(90)
            $dialog.Height = [Terminal.Gui.Dim]::Percent(90)

            # Post header info
            $headerText = "📍 r/$($post.Subreddit) │ 👤 u/$($post.Author) │ ⬆ $($post.Score) │ 💬 $($post.NumComments)"
            $headerLabel = [Terminal.Gui.Label]::new()
            $headerLabel.Text = $headerText
            $headerLabel.X = 1
            $headerLabel.Y = 0
            $headerLabel.Width = [Terminal.Gui.Dim]::Fill()
            $dialog.Add($headerLabel)

            # Title
            $titleLabel = [Terminal.Gui.Label]::new()
            $titleLabel.Text = $post.Title
            $titleLabel.X = 1
            $titleLabel.Y = 1
            $titleLabel.Width = [Terminal.Gui.Dim]::Fill()
            $dialog.Add($titleLabel)

            # Separator
            $sepLabel = [Terminal.Gui.Label]::new()
            $sepLabel.Text = ("-" * 80)
            $sepLabel.X = 1
            $sepLabel.Y = 2
            $dialog.Add($sepLabel)

            # Content area - TextView for scrolling
            $contentView = [Terminal.Gui.TextView]::new()
            $contentView.X = 1
            $contentView.Y = 3
            $contentView.Width = [Terminal.Gui.Dim]::Fill(1)
            $contentView.Height = [Terminal.Gui.Dim]::Fill(2)
            $contentView.ReadOnly = $true
            $contentView.WordWrap = $true

            # Build content
            $contentLines = [System.Collections.Generic.List[string]]::new()

            # Add self text if present
            if (-not [string]::IsNullOrWhiteSpace($post.SelfText)) {
                $contentLines.Add("--- POST CONTENT ---")
                $contentLines.Add("")
                foreach ($line in ($post.SelfText -split "`n")) {
                    $contentLines.Add($line)
                }
                $contentLines.Add("")
                $contentLines.Add("--- COMMENTS ---")
                $contentLines.Add("")
            } else {
                if ($post.IsLink) {
                    $contentLines.Add("Link: $($post.LinkUrl)")
                    $contentLines.Add("")
                }
                $contentLines.Add("--- COMMENTS ---")
                $contentLines.Add("")
            }

            # Show loading message
            $contentLines.Add("Loading comments...")
            $contentView.Text = ($contentLines -join "`n")
            $dialog.Add($contentView)

            # Open in Browser button
            $openBtn = [Terminal.Gui.Button]::new()
            $openBtn.Text = "Open in Browser (O)"
            $openBtn.X = [Terminal.Gui.Pos]::Center() - 15
            $openBtn.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
            $openBtn.add_Clicked({
                $urlToOpen = if ($post.IsLink) { $post.LinkUrl } else { $post.Url }
                if ($IsWindows -or $env:OS -match 'Windows') {
                    Start-Process $urlToOpen
                } elseif ($IsMacOS) {
                    Start-Process "open" -ArgumentList $urlToOpen
                } else {
                    Start-Process "xdg-open" -ArgumentList $urlToOpen
                }
            }.GetNewClosure())
            $dialog.Add($openBtn)

            # Close button
            $closeBtn = [Terminal.Gui.Button]::new()
            $closeBtn.Text = "Close (ESC)"
            $closeBtn.X = [Terminal.Gui.Pos]::Center() + 8
            $closeBtn.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
            $closeBtn.add_Clicked({ [Terminal.Gui.Application]::RequestStop() })
            $dialog.Add($closeBtn)

            # Handle O key to open in browser
            $dialog.add_KeyPress({
                param($keyEvent)
                # Check for 'O' or 'o' key (Terminal.Gui v2.x uses Key enum)
                if ($null -ne $keyEvent.Key) {
                    $key = $keyEvent.Key.ToString()
                    if ($key -eq 'O' -or $key -eq 'o') {
                        $urlToOpen = if ($post.IsLink) { $post.LinkUrl } else { $post.Url }
                        if ($IsWindows -or $env:OS -match 'Windows') {
                            Start-Process $urlToOpen
                        } elseif ($IsMacOS) {
                            Start-Process "open" -ArgumentList $urlToOpen
                        } else {
                            Start-Process "xdg-open" -ArgumentList $urlToOpen
                        }
                        $keyEvent.Handled = $true
                    }
                }
            }.GetNewClosure())

            # Load comments in background after dialog shows
            $loadCommentsAction = {
                try {
                    Write-Log -Message "TUI: Fetching comments for permalink: $($post.Permalink)" -Level Debug
                    $comments = Get-RedditComments -Permalink $post.Permalink -Limit 30

                    # Rebuild content with comments
                    $newContent = [System.Collections.Generic.List[string]]::new()

                    if (-not [string]::IsNullOrWhiteSpace($post.SelfText)) {
                        $newContent.Add("📝 POST CONTENT")
                        $newContent.Add("─────────────────────────────────────────")
                        $newContent.Add("")
                        foreach ($line in ($post.SelfText -split "`n")) {
                            $newContent.Add($line)
                        }
                        $newContent.Add("")
                        $newContent.Add("💬 COMMENTS ($($comments.Count) loaded)")
                        $newContent.Add("─────────────────────────────────────────")
                        $newContent.Add("")
                    } else {
                        if ($post.IsLink) {
                            $newContent.Add("🔗 Link: $($post.LinkUrl)")
                            $newContent.Add("")
                        }
                        $newContent.Add("💬 COMMENTS ($($comments.Count) loaded)")
                        $newContent.Add("─────────────────────────────────────────")
                        $newContent.Add("")
                    }

                    if ($comments.Count -gt 0) {
                        $formattedComments = & $formatComments $comments 3
                        foreach ($line in $formattedComments) {
                            $newContent.Add($line)
                        }
                    } else {
                        $newContent.Add("No comments yet.")
                    }

                    $contentView.Text = ($newContent -join "`n")
                    Write-Log -Message "TUI: Displayed $($comments.Count) comments" -Level Debug
                }
                catch {
                    Write-ErrorLog -Message "TUI: Failed to load comments for: $($post.Permalink)" -ErrorRecord $_
                    $contentView.Text = "Failed to load comments: $_"
                }
            }

            # Fetch comments before showing dialog
            & $loadCommentsAction

            # Show dialog
            Write-Log -Message "TUI: About to show post detail dialog" -Level Debug
            Write-Log -Message "TUI: Dialog object null check: $($null -ne $dialog)" -Level Debug
            try {
                [Terminal.Gui.Application]::Run($dialog)
                Write-Log -Message "TUI: Post detail dialog closed normally" -Level Debug
            }
            catch {
                Write-ErrorLog -Message "TUI: CRASH - Failed to run post detail dialog" -ErrorRecord $_
                throw
            }
        }

        # Function to load posts
        $loadPosts = {
            param($subreddit)

            $script:IsSearchResults = $false
            $sort = $script:CurrentSort
            $time = $script:CurrentTime

            Write-Log -Message "TUI: Loading posts for r/$subreddit (sort: $sort, time: $time)" -Level Info

            try {
                $sortInfo = if ($sort -eq 'top') { "$sort/$time" } else { $sort }
                $contentFrame.Title = "r/$subreddit/$sortInfo (Loading...)"
                [Terminal.Gui.Application]::Refresh()

                $script:CurrentPosts = Get-RedditPosts -Subreddit $subreddit -Sort $sort -Time $time -ErrorAction Stop

                $postsList = [System.Collections.Generic.List[string]]::new()
                foreach ($post in $script:CurrentPosts) {
                    $score = $post.Score.ToString().PadLeft(5)
                    $comments = $post.NumComments.ToString().PadLeft(4)
                    $title = $post.Title
                    if ($title.Length -gt 80) {
                        # Truncate to 77 characters + "..." (3 chars) = 80 total
                        $title = $title.Substring(0, 77) + "..."
                    }
                    $postsList.Add("⬆$score 💬$comments │ $title")
                }

                $postsListView.SetSource($postsList)
                $contentFrame.Title = "r/$subreddit/$sortInfo - $($script:CurrentPosts.Count) posts (Enter=view, O=open)"
                Write-Log -Message "TUI: Displayed $($script:CurrentPosts.Count) posts for r/$subreddit" -Level Debug
            }
            catch {
                Write-ErrorLog -Message "TUI: Failed to load r/$subreddit (sort: $sort, time: $time)" -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to load subreddit: $_", @("OK"))
                $contentFrame.Title = "r/$subreddit (Error)"
            }
        }

        # Function to search posts
        $searchPosts = {
            param($query, $subreddit, $globalSearch)

            $script:IsSearchResults = $true

            Write-Log -Message "TUI: Searching for '$query' (global: $globalSearch, subreddit: $subreddit)" -Level Info

            try {
                $searchScope = if ($globalSearch) { "All Reddit" } else { "r/$subreddit" }
                $contentFrame.Title = "Searching $searchScope for '$query'..."
                [Terminal.Gui.Application]::Refresh()

                if ($globalSearch) {
                    $script:CurrentPosts = Search-Reddit -Query $query -ErrorAction Stop
                } else {
                    $script:CurrentPosts = Search-Reddit -Query $query -Subreddit $subreddit -ErrorAction Stop
                }

                $postsList = [System.Collections.Generic.List[string]]::new()
                foreach ($post in $script:CurrentPosts) {
                    $score = $post.Score.ToString().PadLeft(5)
                    $comments = $post.NumComments.ToString().PadLeft(4)
                    $sub = $post.Subreddit
                    $title = $post.Title
                    # Shorter title for search results to show subreddit
                    if ($title.Length -gt 60) {
                        $title = $title.Substring(0, 57) + "..."
                    }
                    $postsList.Add("⬆$score 💬$comments │ r/$sub │ $title")
                }

                $postsListView.SetSource($postsList)
                $resultScope = if ($globalSearch) { "Reddit" } else { "r/$subreddit" }
                $contentFrame.Title = "Search '$query' in $resultScope - $($script:CurrentPosts.Count) results (Enter=view, O=open)"
                Write-Log -Message "TUI: Search returned $($script:CurrentPosts.Count) results" -Level Debug
            }
            catch {
                Write-ErrorLog -Message "TUI: Search failed for '$query' (global: $globalSearch, subreddit: $subreddit)" -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Search failed: $_", @("OK"))
                $contentFrame.Title = "Search Error"
            }
        }

        # Search button click event
        $searchBtn.add_Clicked({
            try {
                $query = $searchInput.Text.ToString().Trim()
                if ($query) {
                    $subreddit = $subredditInput.Text.ToString().Trim()
                    $globalSearch = $searchGlobalCheck.Checked
                    Write-Log -Message "TUI: Search button clicked - query: '$query', global: $globalSearch" -Level Debug
                    & $searchPosts $query $subreddit $globalSearch
                } else {
                    [Terminal.Gui.MessageBox]::Query("Search", "Please enter a search query", @("OK"))
                }
            }
            catch {
                Write-ErrorLog -Message "TUI: Failed to search" -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to search: $_", @("OK"))
            }
        })

        # Post selection event - open post detail
        $postsListView.add_OpenSelectedItem({
            Write-Log -Message "TUI: EVENT - Posts list OpenSelectedItem triggered" -Level Debug
            try {
                $selected = $postsListView.SelectedItem
                Write-Log -Message "TUI: EVENT - Selected post index: $selected, Total posts: $($script:CurrentPosts.Count)" -Level Debug
                if ($selected -ge 0 -and $selected -lt $script:CurrentPosts.Count) {
                    $selectedPost = $script:CurrentPosts[$selected]
                    Write-Log -Message "TUI: EVENT - Opening post detail for: $($selectedPost.Title)" -Level Debug
                    Write-Log -Message "TUI: EVENT - Calling showPostDetail scriptblock" -Level Debug
                    & $showPostDetail $selectedPost
                    Write-Log -Message "TUI: EVENT - showPostDetail completed" -Level Debug
                } else {
                    Write-Log -Message "TUI: EVENT - Invalid selection index: $selected" -Level Warning
                }
            }
            catch {
                Write-ErrorLog -Message "TUI: EVENT - Failed to show post detail" -ErrorRecord $_
                Write-Log -Message "TUI: EVENT - Showing error dialog" -Level Debug
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to open post: $_", @("OK"))
                Write-Log -Message "TUI: EVENT - Error dialog shown" -Level Debug
            }
        })

        # Key press handler for posts list (O to open in browser)
        $postsListView.add_KeyPress({
            param($keyEvent)
            # Check for 'O' or 'o' key (Terminal.Gui v2.x uses Key enum)
            if ($null -ne $keyEvent.Key) {
                $key = $keyEvent.Key.ToString()
                if ($key -eq 'O' -or $key -eq 'o') {
                    $selected = $postsListView.SelectedItem
                    if ($selected -ge 0 -and $selected -lt $script:CurrentPosts.Count) {
                        $selectedPost = $script:CurrentPosts[$selected]
                        $urlToOpen = if ($selectedPost.IsLink) { $selectedPost.LinkUrl } else { $selectedPost.Url }
                        if ($IsWindows -or $env:OS -match 'Windows') {
                            Start-Process $urlToOpen
                        } elseif ($IsMacOS) {
                            Start-Process "open" -ArgumentList $urlToOpen
                        } else {
                            Start-Process "xdg-open" -ArgumentList $urlToOpen
                        }
                        $keyEvent.Handled = $true
                    }
                }
            }
        }.GetNewClosure())

        # Load button click event
        $loadBtn.add_Clicked({
            try {
                $sub = $subredditInput.Text.ToString().Trim()
                if ($sub) {
                    Write-Log -Message "TUI: Load button clicked for: $sub" -Level Debug
                    & $loadPosts $sub
                }
            }
            catch {
                Write-ErrorLog -Message "TUI: Failed to load subreddit" -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to load subreddit: $_", @("OK"))
            }
        })

        # Favorites list selection event
        $favoritesList.add_OpenSelectedItem({
            try {
                $selected = $favoritesList.SelectedItem
                if ($selected -ge 0 -and $selected -lt $favoritesSource.Count) {
                    $fav = $favoritesSource[$selected].ToString().Replace("r/", "")
                    Write-Log -Message "TUI: Favorite selected: $fav" -Level Debug
                    $subredditInput.Text = $fav
                    & $loadPosts $fav
                }
            }
            catch {
                Write-ErrorLog -Message "TUI: Failed to load favorite" -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to load favorite: $_", @("OK"))
            }
        })

        # Add favorite button event
        $addFavBtn.add_Clicked({
            try {
                $sub = $subredditInput.Text.ToString().Trim()
                if ($sub) {
                    Write-Log -Message "TUI: Add favorite button clicked for: $sub" -Level Debug
                    Add-Favorite -Subreddit $sub
                    if ($script:Favorites -contains $sub) {
                        $favoritesSource.Clear()
                        foreach ($fav in $script:Favorites) {
                            $favoritesSource.Add("r/$fav")
                        }
                        $favoritesList.SetSource($favoritesSource)
                    }
                }
            }
            catch {
                Write-ErrorLog -Message "TUI: Failed to add favorite" -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to add favorite: $_", @("OK"))
            }
        })
        
        # Remove favorite button event
        $removeFavBtn.add_Clicked({
            try {
                $selected = $favoritesList.SelectedItem
                if ($selected -ge 0 -and $selected -lt $favoritesSource.Count) {
                    $fav = $favoritesSource[$selected].ToString().Replace("r/", "")
                    Write-Log -Message "TUI: Remove favorite button clicked for: $fav" -Level Debug
                    Remove-Favorite -Subreddit $fav
                    $favoritesSource.Clear()
                    foreach ($f in $script:Favorites) {
                        $favoritesSource.Add("r/$f")
                    }
                    $favoritesList.SetSource($favoritesSource)
                }
            }
            catch {
                Write-ErrorLog -Message "TUI: Failed to remove favorite" -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to remove favorite: $_", @("OK"))
            }
        })

        # Add frames to window
        Write-Log -Message "TUI: Building UI components" -Level Debug
        $win.Add($favoritesFrame)
        $win.Add($contentFrame)
        $top.Add($win)

        # Load initial subreddit
        & $loadPosts $InitialSubreddit

        # Run the application
        Write-Log -Message "TUI: Starting application main loop" -Level Info
        Write-Log -Message "TUI: About to call Terminal.Gui.Application.Run() with explicit toplevel" -Level Debug
        Write-Log -Message "TUI: Application state - Top: $($null -ne $top), Win: $($null -ne $win)" -Level Debug

        try {
            [Terminal.Gui.Application]::Run($top)
            Write-Log -Message "TUI: Application.Run() returned normally" -Level Debug
        }
        catch {
            Write-Log -Message "TUI: CRASH - Exception caught at Application.Run() level" -Level Error
            Write-ErrorLog -Message "TUI: CRASH - Application.Run() threw exception" -ErrorRecord $_
            throw
        }

        Write-Log -Message "TUI: Application main loop ended normally" -Level Debug
    }
    catch {
        Write-ErrorLog -Message "TUI: Unhandled exception in application" -ErrorRecord $_
        throw
    }
    finally {
        Write-Log -Message "TUI: Shutting down application" -Level Info
        try {
            [Terminal.Gui.Application]::Shutdown()
            Write-Log -Message "TUI: Application shutdown complete" -Level Debug
        }
        catch {
            Write-ErrorLog -Message "TUI: Error during shutdown" -ErrorRecord $_
        }
    }
}

#endregion

#region Dependency Management

function Install-PSRedditTUITerminalGui {
    <#
    .SYNOPSIS
        Installs Terminal.Gui dependency for PSRedditTUI
    .DESCRIPTION
        Downloads Terminal.Gui and its NStack.Core dependency from NuGet and extracts them to ~/.psreddittui-packages/.
        Defaults to v1.16.0 which is the stable version used by Microsoft.PowerShell.ConsoleGuiTools.
        Terminal.Gui v2.x has compatibility issues with PowerShell and is not recommended.
    .PARAMETER Version
        The Terminal.Gui version to install (default: 1.16.0 - same as Microsoft.PowerShell.ConsoleGuiTools)
    .PARAMETER NStackVersion
        The NStack.Core version to install (default: 1.0.0 - compatible with Terminal.Gui 1.16.0)
    .PARAMETER Force
        Force reinstallation even if Terminal.Gui is already installed
    .EXAMPLE
        Install-PSRedditTUITerminalGui
        Installs Terminal.Gui 1.16.0 and NStack.Core 1.0.0 to the local package directory
    .EXAMPLE
        Install-PSRedditTUITerminalGui -Version "1.16.0" -Force
        Forces reinstallation of Terminal.Gui 1.16.0 and NStack.Core
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Version = "1.16.0",

        [Parameter(Mandatory = $false)]
        [string]$NStackVersion = "1.0.0",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    try {
        $packageDir = Join-Path $HOME ".psreddittui-packages"
        $terminalGuiExtractPath = Join-Path $packageDir "Terminal.Gui"
        $nstackExtractPath = Join-Path $packageDir "NStack.Core"
        $terminalGuiDllPath = Join-Path $terminalGuiExtractPath "lib/net8.0/Terminal.Gui.dll"
        $nstackDllPath = Join-Path $nstackExtractPath "lib/netstandard2.0/NStack.dll"

        # Check if already installed (skip if -Force)
        if (-not $Force) {
            if ((Test-Path $terminalGuiDllPath) -and (Test-Path $nstackDllPath)) {
                Write-Log -Message "Terminal.Gui and NStack already installed" -Level Info
                Write-Information "Terminal.Gui and NStack are already installed. Use -Force to reinstall." -InformationAction Continue

                # Try to load if not already loaded (NStack first, then Terminal.Gui)
                if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'NStack' })) {
                    try {
                        Add-Type -Path $nstackDllPath -ErrorAction Stop
                        Write-Log -Message "Loaded NStack assembly from: $nstackDllPath" -Level Info
                    }
                    catch {
                        Write-ErrorLog -Message "Failed to load existing NStack assembly" -ErrorRecord $_
                    }
                }

                if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Terminal.Gui' })) {
                    try {
                        Add-Type -Path $terminalGuiDllPath -ErrorAction Stop
                        Write-Log -Message "Loaded Terminal.Gui assembly from: $terminalGuiDllPath" -Level Info
                    }
                    catch {
                        Write-ErrorLog -Message "Failed to load existing Terminal.Gui assembly" -ErrorRecord $_
                    }
                }

                return [PSCustomObject]@{
                    TerminalGuiVersion = $Version
                    NStackVersion = $NStackVersion
                    TerminalGuiPath = $terminalGuiDllPath
                    NStackPath = $nstackDllPath
                    Loaded = $true
                    Message = "Terminal.Gui and NStack already installed"
                }
            }
        }

        # Create package directory
        Write-Log -Message "Creating package directory: $packageDir" -Level Debug
        New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

        # ===== Install NStack.Core first (dependency) =====
        Write-Log -Message "Downloading NStack.Core $NStackVersion from NuGet..." -Level Info
        Write-Information "Downloading NStack.Core $NStackVersion..." -InformationAction Continue

        $nstackNupkgUrl = "https://www.nuget.org/api/v2/package/NStack.Core/$NStackVersion"
        $nstackNupkgPath = Join-Path $packageDir "NStack.Core.$NStackVersion.nupkg"

        Invoke-WebRequest -Uri $nstackNupkgUrl -OutFile $nstackNupkgPath -ErrorAction Stop
        Write-Log -Message "Downloaded NStack.Core to: $nstackNupkgPath" -Level Debug

        # Extract NStack package
        Write-Log -Message "Extracting NStack.Core to: $nstackExtractPath" -Level Info
        Write-Information "Extracting NStack.Core..." -InformationAction Continue

        if (Test-Path $nstackExtractPath) {
            Remove-Item -Path $nstackExtractPath -Recurse -Force
        }

        $nstackZipPath = $nstackNupkgPath -replace '\.nupkg$', '.zip'
        if (Test-Path $nstackZipPath) {
            Remove-Item -Path $nstackZipPath -Force
        }
        Copy-Item -Path $nstackNupkgPath -Destination $nstackZipPath -Force
        Expand-Archive -Path $nstackZipPath -DestinationPath $nstackExtractPath -Force
        Remove-Item -Path $nstackZipPath -Force -ErrorAction SilentlyContinue

        # Find NStack.dll
        if (-not (Test-Path $nstackDllPath)) {
            Write-Log -Message "netstandard2.0 NStack.dll not found, searching for alternatives..." -Level Debug
            $nstackDllPath = Get-ChildItem -Path $nstackExtractPath -Recurse -Filter "NStack.dll" |
                             Select-Object -First 1 -ExpandProperty FullName
        }

        if (-not $nstackDllPath -or -not (Test-Path $nstackDllPath)) {
            $errorMsg = "Could not find NStack.dll in extracted package"
            Write-ErrorLog -Message $errorMsg -ErrorRecord $null
            throw $errorMsg
        }

        Write-Log -Message "Found NStack.dll at: $nstackDllPath" -Level Info
        Write-Information "NStack.Core installed successfully!" -InformationAction Continue

        # ===== Install Terminal.Gui =====
        Write-Log -Message "Downloading Terminal.Gui $Version from NuGet..." -Level Info
        Write-Information "Downloading Terminal.Gui $Version..." -InformationAction Continue

        $terminalGuiNupkgUrl = "https://www.nuget.org/api/v2/package/Terminal.Gui/$Version"
        $terminalGuiNupkgPath = Join-Path $packageDir "Terminal.Gui.$Version.nupkg"

        Invoke-WebRequest -Uri $terminalGuiNupkgUrl -OutFile $terminalGuiNupkgPath -ErrorAction Stop
        Write-Log -Message "Downloaded Terminal.Gui to: $terminalGuiNupkgPath" -Level Debug

        # Extract Terminal.Gui package
        Write-Log -Message "Extracting Terminal.Gui to: $terminalGuiExtractPath" -Level Info
        Write-Information "Extracting Terminal.Gui..." -InformationAction Continue

        if (Test-Path $terminalGuiExtractPath) {
            Remove-Item -Path $terminalGuiExtractPath -Recurse -Force
        }

        $terminalGuiZipPath = $terminalGuiNupkgPath -replace '\.nupkg$', '.zip'
        if (Test-Path $terminalGuiZipPath) {
            Remove-Item -Path $terminalGuiZipPath -Force
        }
        Copy-Item -Path $terminalGuiNupkgPath -Destination $terminalGuiZipPath -Force
        Expand-Archive -Path $terminalGuiZipPath -DestinationPath $terminalGuiExtractPath -Force
        Remove-Item -Path $terminalGuiZipPath -Force -ErrorAction SilentlyContinue

        # Find Terminal.Gui.dll - prefer net8.0 for PowerShell 7.4+
        if (-not (Test-Path $terminalGuiDllPath)) {
            Write-Log -Message "net8.0 Terminal.Gui.dll not found, searching for alternatives..." -Level Debug
            $terminalGuiDllPath = Get-ChildItem -Path $terminalGuiExtractPath -Recurse -Filter "Terminal.Gui.dll" |
                                  Where-Object { $_.FullName -match 'net[78]' } |
                                  Select-Object -First 1 -ExpandProperty FullName
        }

        if (-not $terminalGuiDllPath -or -not (Test-Path $terminalGuiDllPath)) {
            $errorMsg = "Could not find Terminal.Gui.dll in extracted package"
            Write-ErrorLog -Message $errorMsg -ErrorRecord $null
            throw $errorMsg
        }

        Write-Log -Message "Found Terminal.Gui.dll at: $terminalGuiDllPath" -Level Info
        Write-Information "Terminal.Gui installed successfully!" -InformationAction Continue

        # ===== Load assemblies (NStack first, then Terminal.Gui) =====
        # Load NStack first (dependency)
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'NStack' })) {
            Write-Log -Message "Loading NStack assembly..." -Level Info
            Write-Information "Loading NStack assembly..." -InformationAction Continue
            Add-Type -Path $nstackDllPath -ErrorAction Stop
            Write-Log -Message "Successfully loaded NStack assembly" -Level Info
            Write-Information "Loaded: $nstackDllPath" -InformationAction Continue
        }
        else {
            Write-Log -Message "NStack assembly already loaded in current session" -Level Info
        }

        # Load Terminal.Gui
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Terminal.Gui' })) {
            Write-Log -Message "Loading Terminal.Gui assembly..." -Level Info
            Write-Information "Loading Terminal.Gui assembly..." -InformationAction Continue
            Add-Type -Path $terminalGuiDllPath -ErrorAction Stop
            Write-Log -Message "Successfully loaded Terminal.Gui assembly" -Level Info
            Write-Information "Loaded: $terminalGuiDllPath" -InformationAction Continue
        }
        else {
            Write-Log -Message "Terminal.Gui assembly already loaded in current session" -Level Info
        }

        # Return success information
        return [PSCustomObject]@{
            TerminalGuiVersion = $Version
            NStackVersion = $NStackVersion
            TerminalGuiPath = $terminalGuiDllPath
            NStackPath = $nstackDllPath
            Loaded = $true
            Message = "Terminal.Gui and NStack installed and loaded successfully"
        }
    }
    catch {
        Write-ErrorLog -Message "Failed to install Terminal.Gui and NStack" -ErrorRecord $_

        # Provide manual installation instructions
        Write-Host ""
        Write-Host "Automatic installation failed. You can install Terminal.Gui and NStack manually:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Option 1: Using Install-Package (recommended)" -ForegroundColor Cyan
        Write-Host "  # Install NStack.Core first (dependency)" -ForegroundColor White
        Write-Host "  Install-Package -Name NStack.Core -ProviderName NuGet -Scope CurrentUser -RequiredVersion $NStackVersion" -ForegroundColor White
        Write-Host "  Install-Package -Name Terminal.Gui -ProviderName NuGet -Scope CurrentUser -RequiredVersion $Version" -ForegroundColor White
        Write-Host "  Then add the assemblies to PowerShell (NStack first):" -ForegroundColor White
        Write-Host "  Add-Type -Path `"~/.local/share/PackageManagement/NuGet/Packages/NStack.Core.$NStackVersion/lib/netstandard2.0/NStack.dll`"" -ForegroundColor White
        Write-Host "  Add-Type -Path `"~/.local/share/PackageManagement/NuGet/Packages/Terminal.Gui.$Version/lib/net8.0/Terminal.Gui.dll`"" -ForegroundColor White
        Write-Host ""
        Write-Host "Option 2: Manual Download" -ForegroundColor Cyan
        Write-Host "  1. Download NStack.Core: https://www.nuget.org/api/v2/package/NStack.Core/$NStackVersion" -ForegroundColor White
        Write-Host "  2. Download Terminal.Gui: https://www.nuget.org/api/v2/package/Terminal.Gui/$Version" -ForegroundColor White
        Write-Host "  3. Rename .nupkg files to .zip and extract to: $packageDir" -ForegroundColor White
        Write-Host "  4. Load the DLLs (NStack first, then Terminal.Gui):" -ForegroundColor White
        Write-Host "     Add-Type -Path `"$packageDir/NStack.Core/lib/netstandard2.0/NStack.dll`"" -ForegroundColor White
        Write-Host "     Add-Type -Path `"$packageDir/Terminal.Gui/lib/net8.0/Terminal.Gui.dll`"" -ForegroundColor White
        Write-Host ""
        Write-Host "Error details: $_" -ForegroundColor Red
        Write-Host ""

        throw
    }
}

#endregion

Write-Log -Message "PSRedditTUI module loaded successfully" -Level Info

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
    'Set-PSRedditTUILogLevel',
    'Install-PSRedditTUITerminalGui'
)
