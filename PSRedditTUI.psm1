# PSRedditTUI - PowerShell Reddit Terminal UI Module
# Requires PowerShell Core 7+

#region Logging

$script:LogFile = Join-Path ([System.IO.Path]::GetTempPath()) "psreddittui-debug.log"
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
        $logEntry += "`n  Error Type: $($ErrorRecord.Exception.GetType().FullName)"
        $logEntry += "`n  Target Object: $($ErrorRecord.TargetObject)"

        # Add inner exception details if present
        if ($ErrorRecord.Exception.InnerException) {
            $logEntry += "`n  Inner Exception: $($ErrorRecord.Exception.InnerException.GetType().FullName)"
            $logEntry += "`n  Inner Message: $($ErrorRecord.Exception.InnerException.Message)"
        }

        if ($ErrorRecord.InvocationInfo) {
            $logEntry += "`n  Script: $($ErrorRecord.InvocationInfo.ScriptName)"
            $logEntry += "`n  Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
            $logEntry += "`n  Command: $($ErrorRecord.InvocationInfo.MyCommand)"
            $logEntry += "`n  Position: $($ErrorRecord.InvocationInfo.PositionMessage)"
        }

        if ($ErrorRecord.ScriptStackTrace) {
            $logEntry += "`n  Script StackTrace:`n    $($ErrorRecord.ScriptStackTrace -replace "`n", "`n    ")"
        }

        # Add any additional error data
        if ($ErrorRecord.ErrorDetails) {
            $logEntry += "`n  Error Details: $($ErrorRecord.ErrorDetails.Message)"
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

# Auto-load Terminal.Gui and NStack if installed via Install-PSRedditTUITerminalGui
& {
    $packageDir = Join-Path $HOME ".psreddittui-packages"
    $nstackDll = Join-Path $packageDir "NStack.Core/lib/netstandard2.0/NStack.dll"

    # Try to find Terminal.Gui.dll in order of preference: net8.0, net7.0, netstandard2.1
    $terminalGuiDll = $null
    $possiblePaths = @(
        "Terminal.Gui/lib/net8.0/Terminal.Gui.dll",
        "Terminal.Gui/lib/net7.0/Terminal.Gui.dll",
        "Terminal.Gui/lib/netstandard2.1/Terminal.Gui.dll"
    )

    foreach ($path in $possiblePaths) {
        $fullPath = Join-Path $packageDir $path
        if (Test-Path $fullPath) {
            $terminalGuiDll = $fullPath
            Write-Log -Message "Found Terminal.Gui at: $terminalGuiDll" -Level Debug
            break
        }
    }

    if ((Test-Path $nstackDll) -and $terminalGuiDll) {
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
            Write-Log -Message "Failed to auto-load Terminal.Gui" -Level Error -ErrorRecord $_
            Write-Warning "Failed to auto-load Terminal.Gui: $_"
        }
    } else {
        Write-Log -Message "Terminal.Gui not found at expected path" -Level Warning
    }
}

# Module variables
$script:FavoritesFile = Join-Path $HOME ".psreddittui_favorites.json"
$script:Favorites = @()
$script:AfterCursor = $null
$script:LastSearchQuery = $null
$script:LastSearchSubreddit = $null
$script:LastSearchGlobal = $false

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

    $ProgressPreference = 'SilentlyContinue'

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
        $rawContent = $null
        $statusCode = 200
        $contentType = "application/json"

        # Try Invoke-WebRequest first for full response details
        try {
            $webResponse = Invoke-WebRequest -Uri $Url -Method Get -UserAgent $userAgent
            $duration = ((Get-Date) - $startTime).TotalMilliseconds

            $statusCode = $webResponse.StatusCode
            $contentType = $webResponse.Headers['Content-Type']
            $rawContent = $webResponse.Content

            Write-Log -Message "Reddit API response: Status=$statusCode, ContentType=$contentType, Size=$($rawContent.Length)bytes, Duration=${duration}ms" -Level Debug
        }
        catch [System.ArgumentOutOfRangeException] {
            # Invoke-WebRequest fails with ArgumentOutOfRangeException on some Reddit responses
            # This is a known PowerShell Core bug with large Unicode content
            # Fallback to Invoke-RestMethod which handles these cases better
            Write-Log -Message "Invoke-WebRequest failed with ArgumentOutOfRangeException, falling back to Invoke-RestMethod" -Level Debug

            try {
                $restStartTime = Get-Date
                $response = Invoke-RestMethod -Uri $Url -Method Get -UserAgent $userAgent
                $duration = ((Get-Date) - $restStartTime).TotalMilliseconds

                Write-Log -Message "Reddit API response (via RestMethod): Status=200, Duration=${duration}ms" -Level Debug
                Write-Log -Message "JSON parsed successfully (via RestMethod fallback)" -Level Debug

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
                Write-Log -Message "Invoke-RestMethod also failed for: $Url" -Level Error -ErrorRecord $_
                Write-Error "Failed to fetch Reddit data: $_"
                return $null
            }
        }

        # Log first portion of response for debugging (truncate if too long)
        if ($rawContent) {
            try {
                $previewLength = [Math]::Min($rawContent.Length, 500)
                $preview = $rawContent.Substring(0, $previewLength)
                if ($rawContent.Length -gt 500) {
                    $preview += "... [truncated, total: $($rawContent.Length) chars]"
                }
                Write-Log -Message "Response preview: $preview" -Level Debug
            }
            catch {
                Write-Log -Message "Response size: $($rawContent.Length) chars (preview failed)" -Level Debug
            }

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
    }
    catch {
        $errorContext = "URL: $Url"

        # Add HTTP response details if available
        if ($_.Exception.Response) {
            $errorContext += " | HTTP Status: $($_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)"
        }

        # Add specific error type information
        if ($_.Exception -is [System.Net.WebException]) {
            $errorContext += " | Network Error: $($_.Exception.Status)"
        }

        Write-Log -Message "Failed to fetch Reddit data - $errorContext" -Level Error -ErrorRecord $_
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
        [ValidatePattern('^[a-zA-Z0-9_+\-]+$')]
        [string]$Subreddit,

        [Parameter(Mandatory = $false)]
        [ValidateSet('hot', 'new', 'top', 'rising')]
        [string]$Sort = 'hot',

        [Parameter(Mandatory = $false)]
        [ValidateSet('hour', 'day', 'week', 'month', 'year', 'all')]
        [string]$Time = 'day',

        [Parameter(Mandatory = $false)]
        [string]$After
    )

    $isMultireddit = $Subreddit -match '\+'
    Write-Log -Message "Getting posts from r/$Subreddit (sort: $Sort, time: $Time, after: $After, multireddit: $isMultireddit)" -Level Info

    $url = "https://www.reddit.com/r/$Subreddit/$Sort"
    Write-Log -Message "Get-RedditPosts: base URL = $url" -Level Debug

    # Add time filter for 'top' sort
    if ($Sort -eq 'top') {
        $url += "?t=$Time"
        Write-Log -Message "Get-RedditPosts: appended time filter, URL = $url" -Level Debug
    }

    # Append pagination cursor
    if ($After) {
        $separator = if ($url -match '\?') { '&' } else { '?' }
        $url += "${separator}after=$After"
        Write-Log -Message "Get-RedditPosts: appended pagination cursor '$After', URL = $url" -Level Debug
    }

    Write-Log -Message "Get-RedditPosts: calling Get-RedditData with final URL = $url" -Level Debug
    $data = Get-RedditData -Url $url

    # Capture pagination cursor
    $script:AfterCursor = if ($data -and $data.data) { $data.data.after } else { $null }
    Write-Log -Message "Get-RedditPosts: response received, data null=$($null -eq $data), AfterCursor=$($script:AfterCursor)" -Level Debug

    if ($data -and $data.data -and $data.data.children) {
        $postCount = $data.data.children.Count
        Write-Log -Message "Get-RedditPosts: retrieved $postCount posts from r/$Subreddit (after cursor: $($script:AfterCursor))" -Level Debug
        $postIndex = 0
        return $data.data.children | ForEach-Object {
            Write-Log -Message "Get-RedditPosts: post[$postIndex] title='$($_.data.title)' post_hint='$($_.data.post_hint)' is_video=$($_.data.is_video) subreddit=$($_.data.subreddit)" -Level Debug
            $postIndex++
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
                PostHint = $_.data.post_hint
                IsVideo = [bool]$_.data.is_video
            }
        }
    }

    Write-Log -Message "Get-RedditPosts: no data returned for r/$Subreddit" -Level Warning
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
        [string]$Time = 'all',

        [Parameter(Mandatory = $false)]
        [string]$After
    )

    Write-Log -Message "Searching Reddit: '$Query' (subreddit: $Subreddit, sort: $Sort, time: $Time, after: $After)" -Level Info

    # URL encode the query
    $encodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)

    # Build URL
    if ($Subreddit) {
        $url = "https://www.reddit.com/r/$Subreddit/search.json?q=$encodedQuery&restrict_sr=on&sort=$Sort&t=$Time"
    } else {
        $url = "https://www.reddit.com/search.json?q=$encodedQuery&sort=$Sort&t=$Time"
    }

    # Append pagination cursor
    if ($After) {
        $url += "&after=$After"
        Write-Log -Message "Search-Reddit: appended pagination cursor '$After'" -Level Debug
    }

    $ProgressPreference = 'SilentlyContinue'

    try {
        Write-Log -Message "Search-Reddit: final URL = $url" -Level Debug

        # Use module version for User-Agent
        $moduleVersion = $MyInvocation.MyCommand.Module.Version
        $userAgent = "PSRedditTUI/$moduleVersion"

        $startTime = Get-Date
        $response = Invoke-RestMethod -Uri $url -Method Get -UserAgent $userAgent
        $duration = ((Get-Date) - $startTime).TotalMilliseconds

        Write-Log -Message "Search completed in ${duration}ms" -Level Debug

        # Capture pagination cursor
        $script:AfterCursor = if ($response -and $response.data) { $response.data.after } else { $null }
        Write-Log -Message "Search-Reddit: response received, data null=$($null -eq $response), AfterCursor=$($script:AfterCursor)" -Level Debug

        if ($response -and $response.data -and $response.data.children) {
            $resultCount = $response.data.children.Count
            Write-Log -Message "Search-Reddit: returned $resultCount results (after cursor: $($script:AfterCursor))" -Level Info

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
                    PostHint = $_.data.post_hint
                    IsVideo = [bool]$_.data.is_video
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
        Opens an interactive Terminal UI using Terminal.Gui for browsing Reddit with emoji icons and a favorites sidebar.

        Uses the default ConsoleDriver with full emoji support (⬆ 💬 📍 👤 📝 🔗) for best compatibility.
    .PARAMETER InitialSubreddit
        The subreddit to load initially (default: "popular")
    .EXAMPLE
        Show-RedditTUI
        Launches the TUI with the popular subreddit
    .EXAMPLE
        Show-RedditTUI -InitialSubreddit "powershell"
        Launches the TUI with the PowerShell subreddit
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InitialSubreddit = "popular"
    )
    
    $moduleVersion = (Get-Module PSRedditTUI).Version
    Write-Log -Message "Show-RedditTUI starting with initial subreddit: $InitialSubreddit" -Level Info
    Write-Log -Message "Debug log file: $script:LogFile" -Level Info
    Write-Log -Message "PowerShell version: $($PSVersionTable.PSVersion) OS: $($PSVersionTable.OS)" -Level Debug
    Write-Verbose "PSRedditTUI debug log: $script:LogFile"

    # Check if Terminal.Gui is available
    try {
        $null = [Terminal.Gui.Application]
        Write-Log -Message "Terminal.Gui is available" -Level Debug
    }
    catch {
        Write-Log -Message "Terminal.Gui is not available - run Install-PSRedditTUITerminalGui" -Level Error -ErrorRecord $_
        Write-Error "Terminal.Gui is not available. Run 'Install-PSRedditTUITerminalGui' to install the dependency, or manually install the Terminal.Gui .NET assembly."
        return
    }

    # Load favorites
    Get-Favorites | Out-Null

    # Initialize Terminal.Gui with default driver
    # Check if Application is already initialized and shut it down first
    if ($null -ne [Terminal.Gui.Application]::Driver) {
        Write-Log -Message "Application already initialized, shutting down to reinitialize" -Level Debug
        [Terminal.Gui.Application]::Shutdown()
    }

    # Always use emojis - they work fine in modern terminals without NetDriver
    # NetDriver causes freezing issues, so we use the default ConsoleDriver instead
    $script:UsingSystemConsole = $true

    Write-Log -Message "Initializing Terminal.Gui Application with default ConsoleDriver" -Level Debug
    [Terminal.Gui.Application]::Init()
    Write-Log -Message "Terminal.Gui initialized successfully with emoji support" -Level Info

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
                    [Terminal.Gui.MessageBox]::Query("About", "PSRedditTUI v$moduleVersion`nA PowerShell Reddit Terminal Browser`nPress ESC to close", @("OK"))
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
                Write-Log -Message "TUI: EVENT - Failed in sort combo handler" -Level Error -ErrorRecord $_
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
                Write-Log -Message "TUI: Failed to change time filter" -Level Error -ErrorRecord $_
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
        Write-Log -Message "TUI: Creating postsListView at Y=4, Height=Fill(1) to leave room for Load More button" -Level Debug
        $postsListView = [Terminal.Gui.ListView]::new()
        $postsListView.X = 0
        $postsListView.Y = 4
        $postsListView.Width = [Terminal.Gui.Dim]::Fill()
        $postsListView.Height = [Terminal.Gui.Dim]::Fill(1)
        $contentFrame.Add($postsListView)

        # Load More button (hidden by default)
        Write-Log -Message "TUI: Creating Load More button (hidden by default)" -Level Debug
        $loadMoreBtn = [Terminal.Gui.Button]::new()
        $loadMoreBtn.Text = "Load More..."
        $loadMoreBtn.X = [Terminal.Gui.Pos]::Center()
        $loadMoreBtn.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
        $loadMoreBtn.Visible = $false
        $contentFrame.Add($loadMoreBtn)
        Write-Log -Message "TUI: Load More button added to contentFrame" -Level Debug

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
                $opTag = if ($comment.IsOP) { " [OP]" } else { "" }
                $scoreStr = if ($comment.Score -ge 0) { "+$($comment.Score)" } else { "$($comment.Score)" }

                # Author line
                $lines.Add("${indent}[$scoreStr] u/$($comment.Author)$opTag")

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

            # Copy parent-scope refs into locals so .GetNewClosure() captures them
            $listView = $postsListView
            $logFile = $script:LogFile

            Write-Log -Message "TUI: Opening post detail for: $($post.Title)" -Level Info

            # Create dialog
            # Use Window instead of Dialog to avoid ESC closing the entire app
            $dialog = [Terminal.Gui.Window]::new("Post Details (ESC to close)")
            $dialog.X = [Terminal.Gui.Pos]::Center()
            $dialog.Y = [Terminal.Gui.Pos]::Center()
            $dialog.Width = [Terminal.Gui.Dim]::Percent(90)
            $dialog.Height = [Terminal.Gui.Dim]::Percent(90)
            $dialog.Modal = $true

            # Post header info
            # Use emojis when NetDriver (UseSystemConsole) is enabled for better Unicode support
            $locationIcon = if ($script:UsingSystemConsole) { "📍" } else { "@" }
            $userIcon = if ($script:UsingSystemConsole) { "👤" } else { "u" }
            $upvoteIcon = if ($script:UsingSystemConsole) { "⬆" } else { "^" }
            $commentIcon = if ($script:UsingSystemConsole) { "💬" } else { "#" }

            $headerText = "$locationIcon r/$($post.Subreddit) | $userIcon u/$($post.Author) | $upvoteIcon $($post.Score) | $commentIcon $($post.NumComments)"
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
                Start-Process $urlToOpen
            }.GetNewClosure())
            $dialog.Add($openBtn)

            # Close button
            $closeBtn = [Terminal.Gui.Button]::new()
            $closeBtn.Text = "Close (ESC)"
            $closeBtn.X = [Terminal.Gui.Pos]::Center() + 8
            $closeBtn.Y = [Terminal.Gui.Pos]::AnchorEnd(1)
            $closeBtn.add_Clicked({
                $top = [Terminal.Gui.Application]::Top
                $top.Remove($dialog)
                $listView.SetFocus()
            }.GetNewClosure())
            $dialog.Add($closeBtn)

            # Handle O key to open in browser and ESC to close
            # Terminal.Gui v1.x passes KeyEventEventArgs; key is at .KeyEvent.Key
            $dialog.add_KeyPress({
                param($keyEvent)
                if ($null -eq $keyEvent) { return }
                # Resolve the Key from either .KeyEvent.Key or .Key depending on TG version
                $k = $null
                if ($null -ne $keyEvent.KeyEvent) { $k = $keyEvent.KeyEvent.Key }
                elseif ($null -ne $keyEvent.Key) { $k = $keyEvent.Key }
                if ($null -eq $k) { return }
                $key = $k.ToString()
                if ($key -eq 'Esc' -or $key -eq 'Escape') {
                    $top = [Terminal.Gui.Application]::Top
                    $top.Remove($dialog)
                    $listView.SetFocus()
                    $keyEvent.Handled = $true
                }
                elseif ($key -eq 'O' -or $key -eq 'o') {
                    $urlToOpen = if ($post.IsLink) { $post.LinkUrl } else { $post.Url }
                    Start-Process $urlToOpen
                    $keyEvent.Handled = $true
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
                        $newContent.Add("--- POST CONTENT ---")
                        $newContent.Add("")
                        foreach ($line in ($post.SelfText -split "`n")) {
                            $newContent.Add($line)
                        }
                        $newContent.Add("")
                        $newContent.Add("--- COMMENTS ($($comments.Count)) ---")
                        $newContent.Add("")
                    } else {
                        if ($post.IsLink) {
                            $newContent.Add("Link: $($post.LinkUrl)")
                            $newContent.Add("")
                        }
                        $newContent.Add("--- COMMENTS ($($comments.Count)) ---")
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
                    $errorDetails = "permalink=$($post.Permalink)"
                    $errorDetails += " | Exception: $($_.Exception.GetType().Name)"
                    if ($_.Exception.Message) {
                        $errorDetails += " | Message: $($_.Exception.Message)"
                    }
                    if ($_.Exception.InnerException) {
                        $errorDetails += " | Inner: $($_.Exception.InnerException.Message)"
                    }
                    Write-Log -Message "TUI: Failed to load comments - $errorDetails" -Level Error -ErrorRecord $_
                    $contentView.Text = "Failed to load comments: $($_.Exception.Message)`n`nCheck the log file for more details: Get-PSRedditTUILog"
                }
            }

            # Fetch comments before showing dialog
            & $loadCommentsAction

            # Show dialog - Don't use Application.Run() from within event handler as it creates nested event loop
            # Instead, add to top and set focus, letting main loop handle it
            Write-Log -Message "TUI: About to show post detail dialog" -Level Debug
            Write-Log -Message "TUI: Dialog object null check: $($null -ne $dialog)" -Level Debug
            try {
                $top = [Terminal.Gui.Application]::Top
                Write-Log -Message "TUI: top null check: $($null -ne $top)" -Level Debug
                $top.Add($dialog)
                Write-Log -Message "TUI: Dialog added to top" -Level Debug
                $dialog.SetFocus()
                Write-Log -Message "TUI: Focus set on dialog" -Level Debug
            }
            catch {
                Write-Log -Message "TUI: CRASH - Failed to show post detail dialog" -Level Error -ErrorRecord $_
                throw
            }
        }

        # Function to get post type tag from post_hint/is_video
        # Uses short ASCII tags that render reliably in Terminal.Gui
        $getTypeTag = {
            param($post)
            if ($post.IsVideo) { return '[vid]' }
            switch ($post.PostHint) {
                'image'         { return '[img]' }
                'hosted:video'  { return '[vid]' }
                'rich:video'    { return '[vid]' }
                'link'          { return '[lnk]' }
                'self'          { return '[txt]' }
                default         { return '[txt]' }
            }
        }

        # Function to load posts
        $loadPosts = {
            param($subreddit)

            $script:IsSearchResults = $false
            $script:AfterCursor = $null
            $sort = $script:CurrentSort
            $time = $script:CurrentTime

            Write-Log -Message "TUI: Loading posts for r/$subreddit (sort: $sort, time: $time)" -Level Info

            try {
                Write-Log -Message "TUI: loadPosts started for r/$subreddit" -Level Debug
                $sortInfo = if ($sort -eq 'top') { "$sort/$time" } else { $sort }
                $contentFrame.Title = "r/$subreddit/$sortInfo (Loading...)"
                Write-Log -Message "TUI: Title updated to show Loading message" -Level Debug
                # Don't call Application.Refresh() here - it causes deadlocks with NetDriver in event handler context
                # The UI will update automatically on the next event loop iteration

                $script:CurrentPosts = Get-RedditPosts -Subreddit $subreddit -Sort $sort -Time $time -ErrorAction Stop
                Write-Log -Message "TUI: API call completed, building posts list" -Level Debug

                $postsList = [System.Collections.Generic.List[string]]::new()

                foreach ($post in $script:CurrentPosts) {
                    $tag = & $getTypeTag $post
                    $score = $post.Score.ToString().PadLeft(6)
                    $comments = $post.NumComments.ToString().PadLeft(4)
                    $title = $post.Title
                    if ($title.Length -gt 75) {
                        $title = $title.Substring(0, 72) + "..."
                    }
                    $postsList.Add("$tag $score ^  $comments # | $title")
                }

                Write-Log -Message "TUI: About to call SetSource with $($postsList.Count) items" -Level Debug
                $postsListView.SetSource($postsList)
                Write-Log -Message "TUI: SetSource completed successfully" -Level Debug

                $contentFrame.Title = "r/$subreddit/$sortInfo - $($script:CurrentPosts.Count) posts (Enter=view, O=open)"
                Write-Log -Message "TUI: Displayed $($script:CurrentPosts.Count) posts for r/$subreddit" -Level Debug

                # Show/hide Load More button based on pagination cursor
                $hasMore = [bool]$script:AfterCursor
                Write-Log -Message "TUI: loadPosts: AfterCursor='$($script:AfterCursor)' hasMore=$hasMore, showing Load More button=$hasMore" -Level Debug
                $loadMoreBtn.Visible = $hasMore

                # Set focus to posts list to ensure it's interactive
                Write-Log -Message "TUI: About to call SetFocus on posts list" -Level Debug
                $postsListView.SetFocus()
                Write-Log -Message "TUI: SetFocus completed, loadPosts finished successfully" -Level Debug
            }
            catch {
                $errorDetails = "subreddit=r/$subreddit, sort=$sort, time=$time"
                $errorDetails += " | Exception: $($_.Exception.GetType().Name)"
                if ($_.Exception.Message) {
                    $errorDetails += " | Message: $($_.Exception.Message)"
                }
                Write-Log -Message "TUI: Failed to load posts - $errorDetails" -Level Error -ErrorRecord $_

                $userMessage = "Failed to load subreddit: $($_.Exception.Message)"
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", $userMessage, @("OK"))
                $contentFrame.Title = "r/$subreddit (Error)"
            }
        }

        # Function to search posts
        $searchPosts = {
            param($query, $subreddit, $globalSearch)

            $script:IsSearchResults = $true
            $script:AfterCursor = $null
            $script:LastSearchQuery = $query
            $script:LastSearchSubreddit = $subreddit
            $script:LastSearchGlobal = $globalSearch

            Write-Log -Message "TUI: searchPosts: query='$query' global=$globalSearch subreddit='$subreddit'" -Level Info
            Write-Log -Message "TUI: searchPosts: reset AfterCursor to null, stored search params for pagination replay" -Level Debug

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
                    $tag = & $getTypeTag $post
                    $score = $post.Score.ToString().PadLeft(6)
                    $comments = $post.NumComments.ToString().PadLeft(4)
                    $sub = $post.Subreddit
                    $title = $post.Title
                    if ($title.Length -gt 55) {
                        $title = $title.Substring(0, 52) + "..."
                    }
                    $postsList.Add("$tag $score ^  $comments # | r/$sub | $title")
                }

                $postsListView.SetSource($postsList)
                $resultScope = if ($globalSearch) { "Reddit" } else { "r/$subreddit" }
                $contentFrame.Title = "Search '$query' in $resultScope - $($script:CurrentPosts.Count) results (Enter=view, O=open)"
                Write-Log -Message "TUI: Search returned $($script:CurrentPosts.Count) results" -Level Debug

                # Show/hide Load More button based on pagination cursor
                $hasMore = [bool]$script:AfterCursor
                Write-Log -Message "TUI: searchPosts: AfterCursor='$($script:AfterCursor)' hasMore=$hasMore, showing Load More button=$hasMore" -Level Debug
                $loadMoreBtn.Visible = $hasMore
            }
            catch {
                $errorDetails = "query='$query', global=$globalSearch"
                if (-not $globalSearch) {
                    $errorDetails += ", subreddit=$subreddit"
                }
                $errorDetails += " | Exception: $($_.Exception.GetType().Name)"
                if ($_.Exception.Message) {
                    $errorDetails += " | Message: $($_.Exception.Message)"
                }
                Write-Log -Message "TUI: Search failed - $errorDetails" -Level Error -ErrorRecord $_

                $userMessage = "Search failed: $($_.Exception.Message)"
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", $userMessage, @("OK"))
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
                Write-Log -Message "TUI: Failed to search" -Level Error -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to search: $_", @("OK"))
            }
        })

        # Load More button click event
        $loadMoreBtn.add_Clicked({
            try {
                $cursor = $script:AfterCursor
                Write-Log -Message "TUI: LoadMore: clicked, cursor='$cursor' IsSearchResults=$($script:IsSearchResults)" -Level Debug
                if (-not $cursor) {
                    Write-Log -Message "TUI: LoadMore: no cursor available, returning early" -Level Debug
                    return
                }

                Write-Log -Message "TUI: LoadMore: fetching next page with cursor='$cursor'" -Level Info

                if ($script:IsSearchResults) {
                    # Paginate search results
                    $q = $script:LastSearchQuery
                    $sub = $script:LastSearchSubreddit
                    $global = $script:LastSearchGlobal
                    Write-Log -Message "TUI: LoadMore: search pagination - query='$q' subreddit='$sub' global=$global" -Level Debug

                    if ($global) {
                        $newPosts = Search-Reddit -Query $q -After $cursor -ErrorAction Stop
                    } else {
                        $newPosts = Search-Reddit -Query $q -Subreddit $sub -After $cursor -ErrorAction Stop
                    }
                } else {
                    # Paginate subreddit posts
                    $sub = $subredditInput.Text.ToString().Trim()
                    $sort = $script:CurrentSort
                    $time = $script:CurrentTime
                    Write-Log -Message "TUI: LoadMore: subreddit pagination - sub='$sub' sort=$sort time=$time" -Level Debug
                    $newPosts = Get-RedditPosts -Subreddit $sub -Sort $sort -Time $time -After $cursor -ErrorAction Stop
                }

                $newCount = if ($newPosts) { @($newPosts).Count } else { 0 }
                Write-Log -Message "TUI: LoadMore: API returned $newCount new posts, new AfterCursor='$($script:AfterCursor)'" -Level Debug

                if ($newPosts -and $newCount -gt 0) {
                    $prevCount = $script:CurrentPosts.Count
                    $script:CurrentPosts = @($script:CurrentPosts) + @($newPosts)
                    Write-Log -Message "TUI: LoadMore: appended $newCount posts ($prevCount -> $($script:CurrentPosts.Count) total)" -Level Debug

                    # Rebuild the list view
                    $postsList = [System.Collections.Generic.List[string]]::new()

                    foreach ($post in $script:CurrentPosts) {
                        $tag = & $getTypeTag $post
                        $score = $post.Score.ToString().PadLeft(6)
                        $comments = $post.NumComments.ToString().PadLeft(4)

                        if ($script:IsSearchResults) {
                            $sub = $post.Subreddit
                            $title = $post.Title
                            if ($title.Length -gt 55) { $title = $title.Substring(0, 52) + "..." }
                            $postsList.Add("$tag $score ^  $comments # | r/$sub | $title")
                        } else {
                            $title = $post.Title
                            if ($title.Length -gt 75) { $title = $title.Substring(0, 72) + "..." }
                            $postsList.Add("$tag $score ^  $comments # | $title")
                        }
                    }

                    Write-Log -Message "TUI: LoadMore: rebuilding ListView with $($postsList.Count) items" -Level Debug
                    $postsListView.SetSource($postsList)
                    Write-Log -Message "TUI: LoadMore: ListView updated" -Level Debug
                } else {
                    Write-Log -Message "TUI: LoadMore: no new posts returned" -Level Debug
                }

                # Show/hide button based on new cursor
                $hasMore = [bool]$script:AfterCursor
                Write-Log -Message "TUI: LoadMore: done, new AfterCursor='$($script:AfterCursor)' hasMore=$hasMore" -Level Debug
                $loadMoreBtn.Visible = $hasMore
            }
            catch {
                Write-Log -Message "TUI: Load More failed" -Level Error -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to load more: $($_.Exception.Message)", @("OK"))
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
                Write-Log -Message "TUI: EVENT - Failed to show post detail" -Level Error -ErrorRecord $_
                Write-Log -Message "TUI: EVENT - Showing error dialog" -Level Debug
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to open post: $_", @("OK"))
                Write-Log -Message "TUI: EVENT - Error dialog shown" -Level Debug
            }
        })

        # Key press handler for posts list (O to open in browser)
        $postsListView.add_KeyPress({
            param($keyEvent)
            if ($null -eq $keyEvent) { return }
            $k = $null
            if ($null -ne $keyEvent.KeyEvent) { $k = $keyEvent.KeyEvent.Key }
            elseif ($null -ne $keyEvent.Key) { $k = $keyEvent.Key }
            if ($null -eq $k) { return }
            $key = $k.ToString()
            if ($key -eq 'O' -or $key -eq 'o') {
                $selected = $postsListView.SelectedItem
                if ($selected -ge 0 -and $selected -lt $script:CurrentPosts.Count) {
                    $selectedPost = $script:CurrentPosts[$selected]
                    $urlToOpen = if ($selectedPost.IsLink) { $selectedPost.LinkUrl } else { $selectedPost.Url }
                    Start-Process $urlToOpen
                    $keyEvent.Handled = $true
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
                Write-Log -Message "TUI: Failed to load subreddit" -Level Error -ErrorRecord $_
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
                    Write-Log -Message "TUI: Favorite selection complete" -Level Debug
                }
            }
            catch {
                Write-Log -Message "TUI: Failed to load favorite" -Level Error -ErrorRecord $_
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
                Write-Log -Message "TUI: Failed to add favorite" -Level Error -ErrorRecord $_
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
                Write-Log -Message "TUI: Failed to remove favorite" -Level Error -ErrorRecord $_
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to remove favorite: $_", @("OK"))
            }
        })

        # Add frames to window
        Write-Log -Message "TUI: Building UI components" -Level Debug
        $win.Add($favoritesFrame)
        $win.Add($contentFrame)
        $top.Add($win)

        # Create status bar with keyboard shortcut hints
        # Use [Terminal.Gui.Key]0 for display-only hints to avoid CLS casing
        # ambiguity (Terminal.Gui Key enum has both upper and lower letter variants)
        Write-Log -Message "TUI: Creating StatusBar with shortcut hints" -Level Debug
        $ctrlQ = [Terminal.Gui.Key]([uint32][Terminal.Gui.Key]::CtrlMask -bor [uint32][char]'q')
        Write-Log -Message "TUI: StatusBar: Ctrl+Q key value = $([int]$ctrlQ)" -Level Debug
        $statusBar = [Terminal.Gui.StatusBar]::new(@(
            [Terminal.Gui.StatusItem]::new(([Terminal.Gui.Key]0), "~Enter~ View", $null),
            [Terminal.Gui.StatusItem]::new(([Terminal.Gui.Key]0), "~O~ Open", $null),
            [Terminal.Gui.StatusItem]::new(([Terminal.Gui.Key]0), "~Tab~ Navigate", $null),
            [Terminal.Gui.StatusItem]::new($ctrlQ, "~^Q~ Quit", { [Terminal.Gui.Application]::RequestStop() })
        ))
        Write-Log -Message "TUI: StatusBar created with 4 items, adding to top" -Level Debug
        $top.Add($statusBar)
        Write-Log -Message "TUI: StatusBar added to top" -Level Debug

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
            $errorMsg = "TUI: CRASH - Exception in Application.Run()"
            $errorMsg += " | Exception Type: $($_.Exception.GetType().FullName)"
            $errorMsg += " | Message: $($_.Exception.Message)"
            if ($_.Exception.InnerException) {
                $errorMsg += " | Inner Exception: $($_.Exception.InnerException.GetType().FullName)"
                $errorMsg += " | Inner Message: $($_.Exception.InnerException.Message)"
            }
            Write-Log -Message $errorMsg -Level Error -ErrorRecord $_
            throw
        }

        Write-Log -Message "TUI: Application main loop ended normally" -Level Debug
    }
    catch {
        $errorMsg = "TUI: Unhandled exception in application"
        $errorMsg += " | Exception Type: $($_.Exception.GetType().FullName)"
        $errorMsg += " | Message: $($_.Exception.Message)"
        if ($_.Exception.InnerException) {
            $errorMsg += " | Inner Exception: $($_.Exception.InnerException.GetType().FullName)"
            $errorMsg += " | Inner Message: $($_.Exception.InnerException.Message)"
        }
        Write-Log -Message $errorMsg -Level Error -ErrorRecord $_
        Write-Host "`nAn error occurred in PSRedditTUI. Check the log for details: Get-PSRedditTUILog -Tail 50" -ForegroundColor Red
        throw
    }
    finally {
        Write-Log -Message "TUI: Shutting down application" -Level Info
        try {
            [Terminal.Gui.Application]::Shutdown()
            Write-Log -Message "TUI: Application shutdown complete" -Level Debug
        }
        catch {
            Write-Log -Message "TUI: Error during shutdown" -Level Error -ErrorRecord $_
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
        The NStack.Core version to install (default: 1.1.1 - required by Terminal.Gui 1.16.0)
    .PARAMETER Force
        Force reinstallation even if Terminal.Gui is already installed
    .EXAMPLE
        Install-PSRedditTUITerminalGui
        Installs Terminal.Gui 1.16.0 and NStack.Core 1.1.1 to the local package directory
    .EXAMPLE
        Install-PSRedditTUITerminalGui -Version "1.16.0" -Force
        Forces reinstallation of Terminal.Gui 1.16.0 and NStack.Core
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Version = "1.16.0",

        [Parameter(Mandatory = $false)]
        [string]$NStackVersion = "1.1.1",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    try {
        $packageDir = Join-Path $HOME ".psreddittui-packages"
        $terminalGuiExtractPath = Join-Path $packageDir "Terminal.Gui"
        $nstackExtractPath = Join-Path $packageDir "NStack.Core"
        $nstackDllPath = Join-Path $nstackExtractPath "lib/netstandard2.0/NStack.dll"

        # Try to find Terminal.Gui.dll in order of preference: net8.0, net7.0, netstandard2.1
        $terminalGuiDllPath = $null
        $possiblePaths = @(
            "lib/net8.0/Terminal.Gui.dll",
            "lib/net7.0/Terminal.Gui.dll",
            "lib/netstandard2.1/Terminal.Gui.dll"
        )

        foreach ($path in $possiblePaths) {
            $fullPath = Join-Path $terminalGuiExtractPath $path
            if (Test-Path $fullPath) {
                $terminalGuiDllPath = $fullPath
                break
            }
        }

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
                        Write-Log -Message "Failed to load existing NStack assembly" -Level Error -ErrorRecord $_
                    }
                }

                if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Terminal.Gui' })) {
                    try {
                        Add-Type -Path $terminalGuiDllPath -ErrorAction Stop
                        Write-Log -Message "Loaded Terminal.Gui assembly from: $terminalGuiDllPath" -Level Info
                    }
                    catch {
                        Write-Log -Message "Failed to load existing Terminal.Gui assembly" -Level Error -ErrorRecord $_
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
            Write-Log -Message $errorMsg -Level Error
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

        # Find Terminal.Gui.dll - try preferred paths in order
        if (-not $terminalGuiDllPath -or -not (Test-Path $terminalGuiDllPath)) {
            Write-Log -Message "Searching for Terminal.Gui.dll in extracted package..." -Level Debug
            $terminalGuiDllPath = Get-ChildItem -Path $terminalGuiExtractPath -Recurse -Filter "Terminal.Gui.dll" |
                                  Where-Object { $_.FullName -match 'net[78]|netstandard' } |
                                  Select-Object -First 1 -ExpandProperty FullName
        }

        if (-not $terminalGuiDllPath -or -not (Test-Path $terminalGuiDllPath)) {
            $errorMsg = "Could not find Terminal.Gui.dll in extracted package"
            Write-Log -Message $errorMsg -Level Error
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
        Write-Log -Message "Failed to install Terminal.Gui and NStack" -Level Error -ErrorRecord $_
        throw "Failed to install Terminal.Gui: $_`n`nFor manual installation instructions, run: Get-Help Install-PSRedditTUITerminalGui -Full"
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
    'Set-PSRedditTUILogLevel',
    'Install-PSRedditTUITerminalGui'
)
