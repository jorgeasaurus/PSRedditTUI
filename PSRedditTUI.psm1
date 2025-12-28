# PSRedditTUI - PowerShell Reddit Terminal UI Module
# Requires PowerShell Core 7+

using namespace Terminal.Gui

# Module variables
$script:FavoritesFile = Join-Path $env:HOME ".psreddittui_favorites.json"
$script:Favorites = @()

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
        # Add /.json to the end of the URL if not already present
        if (-not $Url.EndsWith('.json')) {
            $Url = $Url.TrimEnd('/') + '/.json'
        }
        
        Write-Verbose "Fetching data from: $Url"
        
        $response = Invoke-RestMethod -Uri $Url -Method Get -UserAgent "PSRedditTUI/1.0"
        return $response
    }
    catch {
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
    .EXAMPLE
        Get-RedditPosts -Subreddit "powershell" -Sort "hot"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subreddit,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('hot', 'new', 'top', 'rising')]
        [string]$Sort = 'hot'
    )
    
    $url = "https://www.reddit.com/r/$Subreddit/$Sort"
    $data = Get-RedditData -Url $url
    
    if ($data -and $data.data -and $data.data.children) {
        return $data.data.children | ForEach-Object {
            [PSCustomObject]@{
                Title = $_.data.title
                Author = $_.data.author
                Score = $_.data.score
                Subreddit = $_.data.subreddit
                Url = "https://www.reddit.com$($_.data.permalink)"
                Comments = $_.data.num_comments
                Created = [DateTimeOffset]::FromUnixTimeSeconds($_.data.created_utc).LocalDateTime
                SelfText = $_.data.selftext
            }
        }
    }
    
    return @()
}

#endregion

#region Favorites Management

function Get-Favorites {
    <#
    .SYNOPSIS
        Loads favorites from local storage
    #>
    [CmdletBinding()]
    param()
    
    if (Test-Path $script:FavoritesFile) {
        try {
            $script:Favorites = Get-Content $script:FavoritesFile -Raw | ConvertFrom-Json
            return $script:Favorites
        }
        catch {
            Write-Warning "Failed to load favorites: $_"
            $script:Favorites = @()
        }
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
    
    try {
        $script:Favorites | ConvertTo-Json | Set-Content $script:FavoritesFile
        Write-Verbose "Favorites saved to $script:FavoritesFile"
    }
    catch {
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
    
    if ($script:Favorites -notcontains $Subreddit) {
        $script:Favorites += $Subreddit
        Save-Favorites
        Write-Host "Added '$Subreddit' to favorites" -ForegroundColor Green
    }
    else {
        Write-Host "'$Subreddit' is already in favorites" -ForegroundColor Yellow
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
    
    if ($script:Favorites -contains $Subreddit) {
        $script:Favorites = $script:Favorites | Where-Object { $_ -ne $Subreddit }
        Save-Favorites
        Write-Host "Removed '$Subreddit' from favorites" -ForegroundColor Green
    }
    else {
        Write-Host "'$Subreddit' is not in favorites" -ForegroundColor Yellow
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
    
    # Check if Terminal.Gui is available
    try {
        $null = [Terminal.Gui.Application]
    }
    catch {
        Write-Error "Terminal.Gui is not available. Please install it first using: Install-Module -Name Terminal.Gui"
        return
    }
    
    # Load favorites
    Get-Favorites | Out-Null
    
    # Initialize Terminal.Gui
    [Terminal.Gui.Application]::Init()
    
    try {
        # Create main window
        $top = [Terminal.Gui.Application]::Top
        
        # Create main container
        $win = [Terminal.Gui.Window]@{
            Title = "PSRedditTUI - Reddit Terminal Browser"
            X = 0
            Y = 0
            Width = [Terminal.Gui.Dim]::Fill()
            Height = [Terminal.Gui.Dim]::Fill()
        }
        
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
        $favoritesFrame = [Terminal.Gui.FrameView]@{
            Title = "Favorites"
            X = 0
            Y = 1
            Width = 25
            Height = [Terminal.Gui.Dim]::Fill()
        }
        
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
        $addFavBtn = [Terminal.Gui.Button]@{
            Text = "Add"
            X = 0
            Y = [Terminal.Gui.Pos]::AnchorEnd(1)
        }
        
        $removeFavBtn = [Terminal.Gui.Button]@{
            Text = "Remove"
            X = [Terminal.Gui.Pos]::Right($addFavBtn) + 1
            Y = [Terminal.Gui.Pos]::AnchorEnd(1)
        }
        
        $favoritesFrame.Add($addFavBtn)
        $favoritesFrame.Add($removeFavBtn)
        
        # Create main content area (right side)
        $contentFrame = [Terminal.Gui.FrameView]@{
            Title = "r/$InitialSubreddit"
            X = 25
            Y = 1
            Width = [Terminal.Gui.Dim]::Fill()
            Height = [Terminal.Gui.Dim]::Fill(2)
        }
        
        # Subreddit input
        $subredditLabel = [Terminal.Gui.Label]::new()
        $subredditLabel.Text = "Subreddit:"
        $subredditLabel.X = 0
        $subredditLabel.Y = 0
        
        $subredditInput = [Terminal.Gui.TextField]::new()
        $subredditInput.Text = $InitialSubreddit
        $subredditInput.X = [Terminal.Gui.Pos]::Right($subredditLabel) + 1
        $subredditInput.Y = 0
        $subredditInput.Width = 30
        
        $loadBtn = [Terminal.Gui.Button]::new()
        $loadBtn.Text = "Load"
        $loadBtn.X = [Terminal.Gui.Pos]::Right($subredditInput) + 1
        $loadBtn.Y = 0
        
        $contentFrame.Add($subredditLabel)
        $contentFrame.Add($subredditInput)
        $contentFrame.Add($loadBtn)
        
        # Posts list view
        $postsListView = [Terminal.Gui.ListView]::new()
        $postsListView.X = 0
        $postsListView.Y = 2
        $postsListView.Width = [Terminal.Gui.Dim]::Fill()
        $postsListView.Height = [Terminal.Gui.Dim]::Fill()
        
        $contentFrame.Add($postsListView)
        
        # Status bar
        $statusBar = [Terminal.Gui.StatusBar]::new(@(
            [Terminal.Gui.StatusItem]::new([Terminal.Gui.Key]::CtrlMask + [Terminal.Gui.Key]::Q, "~^Q~ Quit", { [Terminal.Gui.Application]::RequestStop() }),
            [Terminal.Gui.StatusItem]::new([Terminal.Gui.Key]::F1, "~F1~ Help", {
                [Terminal.Gui.MessageBox]::Query("Help", "Navigate: Arrow Keys`nSelect: Enter`nQuit: Ctrl+Q or ESC`n`nLoad a subreddit from the input field or select from favorites.", @("OK"))
            })
        ))
        $top.Add($statusBar)
        
        # Function to load posts
        $loadPosts = {
            param($subreddit)
            
            try {
                $contentFrame.Title = "r/$subreddit (Loading...)"
                [Terminal.Gui.Application]::Refresh()
                
                $posts = Get-RedditPosts -Subreddit $subreddit -ErrorAction Stop
                
                $postsList = [System.Collections.Generic.List[string]]::new()
                foreach ($post in $posts) {
                    $score = $post.Score.ToString().PadLeft(5)
                    $comments = $post.Comments.ToString().PadLeft(4)
                    $title = $post.Title
                    if ($title.Length -gt 80) {
                        $title = $title.Substring(0, 77) + "..."
                    }
                    $postsList.Add("[$score ↑] [$comments 💬] $title")
                }
                
                $postsListView.SetSource($postsList)
                $contentFrame.Title = "r/$subreddit - $($posts.Count) posts"
            }
            catch {
                [Terminal.Gui.MessageBox]::ErrorQuery("Error", "Failed to load subreddit: $_", @("OK"))
                $contentFrame.Title = "r/$subreddit (Error)"
            }
        }
        
        # Load button click event
        $loadBtn.add_Clicked({
            $sub = $subredditInput.Text.ToString().Trim()
            if ($sub) {
                & $loadPosts $sub
            }
        })
        
        # Favorites list selection event
        $favoritesList.add_OpenSelectedItem({
            $selected = $favoritesList.SelectedItem
            if ($selected -ge 0 -and $selected -lt $favoritesSource.Count) {
                $fav = $favoritesSource[$selected].ToString().Replace("r/", "")
                $subredditInput.Text = $fav
                & $loadPosts $fav
            }
        })
        
        # Add favorite button event
        $addFavBtn.add_Clicked({
            $sub = $subredditInput.Text.ToString().Trim()
            if ($sub) {
                Add-Favorite -Subreddit $sub
                if ($script:Favorites -contains $sub) {
                    $favoritesSource.Clear()
                    foreach ($fav in $script:Favorites) {
                        $favoritesSource.Add("r/$fav")
                    }
                    $favoritesList.SetSource($favoritesSource)
                }
            }
        })
        
        # Remove favorite button event
        $removeFavBtn.add_Clicked({
            $selected = $favoritesList.SelectedItem
            if ($selected -ge 0 -and $selected -lt $favoritesSource.Count) {
                $fav = $favoritesSource[$selected].ToString().Replace("r/", "")
                Remove-Favorite -Subreddit $fav
                $favoritesSource.Clear()
                foreach ($f in $script:Favorites) {
                    $favoritesSource.Add("r/$f")
                }
                $favoritesList.SetSource($favoritesSource)
            }
        })
        
        # Add frames to window
        $win.Add($favoritesFrame)
        $win.Add($contentFrame)
        $top.Add($win)
        
        # Load initial subreddit
        & $loadPosts $InitialSubreddit
        
        # Run the application
        [Terminal.Gui.Application]::Run()
    }
    finally {
        [Terminal.Gui.Application]::Shutdown()
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Get-RedditData',
    'Get-RedditPosts',
    'Get-Favorites',
    'Add-Favorite',
    'Remove-Favorite',
    'Show-RedditTUI'
)
