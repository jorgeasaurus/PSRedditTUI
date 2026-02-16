#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for PSRedditTUI terminal UI using tmux
.DESCRIPTION
    Launches the real TUI in a tmux session, sends keystrokes, and asserts
    on captured screen output. Requires tmux to be installed.
    Run with: Invoke-Pester ./Tests/PSRedditTUI.TUI.Tests.ps1 -Output Detailed
    Skip in CI by filtering: -ExcludeTag Integration
.NOTES
    Focus behavior: Terminal.Gui v1 with CursesDriver starts focus on the
    favorites list. After loadPosts runs, SetFocus() is called on postsListView.
    The contentFrame remembers this, so 3 forward Tabs from initial state
    reach postsListView. From postsListView, 6 backward Tabs (BTab/Shift-Tab)
    reach the subreddit input field.

    Tab order in contentFrame (forward):
    subredditInput -> loadBtn -> sortCombo -> [timeCombo if visible] ->
    searchInput -> searchBtn -> searchGlobalCheck -> postsListView -> [loadMoreBtn if visible]

    IMPORTANT: After Set-TUISubreddit, the frame title first shows "(Loading...)"
    then changes to "N posts (Enter=view, O=open)" when loadPosts completes.
    Always wait for "Enter=view" after loading a subreddit to ensure loadPosts
    has finished and SetFocus has been called on postsListView.

    NOTE: searchPosts does NOT call SetFocus on postsListView. After a search,
    focus remains on searchBtn. Navigate explicitly before using Focus-TUI* helpers.
#>

BeforeAll {
    # Verify tmux is available
    if (-not (Get-Command tmux -ErrorAction SilentlyContinue)) {
        throw "tmux is required for TUI integration tests. Install with: brew install tmux"
    }

    Import-Module "$PSScriptRoot/TUITestHelpers.psm1" -Force

    # Backup and reset favorites to a known state (prevents stale entries from previous runs)
    $script:favoritesPath = Join-Path $HOME ".psreddittui_favorites.json"
    $script:favoritesBackup = $null
    if (Test-Path $script:favoritesPath) {
        $script:favoritesBackup = Get-Content $script:favoritesPath -Raw
    }
    $knownFavorites = @("lifeprotips", "todayilearned", "askreddit", "popular", "testsubreddit123", "prefixtest999")
    $knownFavorites | ConvertTo-Json | Set-Content $script:favoritesPath -Encoding UTF8

    $script:session = "psreddittui-test-$(Get-Random)"
    $modulePath = Resolve-Path "$PSScriptRoot/../PSRedditTUI.psd1"
    $cmd = "pwsh -NoProfile -Command `"Import-Module '$modulePath'; Show-RedditTUI`""

    Start-TUISession -Name $script:session -Command $cmd

    # Wait for posts to load from the Reddit API (final title has "Enter=view")
    $loaded = Wait-ForTUIText -Name $script:session -Text "Enter=view" -TimeoutSeconds 25
    if (-not $loaded) {
        $screen = Get-TUIScreen -Name $script:session
        Stop-TUISession -Name $script:session
        throw "TUI failed to load within 25 seconds. Screen content:`n$($screen -join "`n")"
    }
}

AfterAll {
    Stop-TUISession -Name $script:session

    # Restore original favorites file
    if ($null -ne $script:favoritesBackup) {
        Set-Content $script:favoritesPath -Value $script:favoritesBackup -Encoding UTF8
    }
}

Describe "TUI Integration" -Tag Integration {

    AfterEach {
        # Save a screenshot on test failure for post-mortem debugging.
        # In Pester 5, the test result is available via $_.Result inside AfterEach.
        if ($_.Result -eq 'Failed') {
            $testLabel = $_.Name -replace '\s+', '_'
            try {
                Save-TUIScreenshot -Name $script:session -Label "FAIL_$testLabel"
            } catch {
                # Session may be dead after Ctrl+Q test; ignore
            }
        }
    }

    It "TUI launches and displays posts" {
        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"

        # Frame title contains "posts" with count
        $content | Should -Match "posts"
    }

    It "Post type tags are visible" {
        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"

        # At least one type tag should be present
        $content | Should -Match "\[(txt|lnk|img|vid)\]"
    }

    It "Status bar is visible" {
        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"

        # Terminal.Gui renders status items -- check for keybinding hints
        $content | Should -Match "Enter"
        $content | Should -Match "Quit"
    }

    It "Load a different subreddit" {
        # Navigate: initial focus is on favorites list.
        # 3 Tabs forward enters contentFrame at postsListView (remembered focus).
        # 6 BTabs backward cycles to subredditInput.
        Focus-TUIPostsList -Name $script:session
        Focus-TUISubredditField -Name $script:session
        Set-TUISubreddit -Name $script:session -Subreddit "powershell"

        # Wait for loading to fully complete (Enter=view only in final title)
        Start-Sleep -Milliseconds 500
        $found = Wait-ForTUIText -Name $script:session -Text "r/powershell/" -TimeoutSeconds 20
        $found | Should -BeTrue
        $ready = Wait-ForTUIText -Name $script:session -Text "Enter=view" -TimeoutSeconds 20
        $ready | Should -BeTrue
    }

    It "Multireddit input accepted" {
        # After loading a subreddit, loadPosts calls SetFocus on postsListView.
        # From postsListView, 6 BTabs reach subredditInput.
        Focus-TUISubredditField -Name $script:session
        Set-TUISubreddit -Name $script:session -Subreddit "powershell+sysadmin"

        # Wait for loading to fully complete
        Start-Sleep -Milliseconds 500
        $found = Wait-ForTUIText -Name $script:session -Text "r/powershell+sysadmin" -TimeoutSeconds 20
        $found | Should -BeTrue
        $ready = Wait-ForTUIText -Name $script:session -Text "Enter=view" -TimeoutSeconds 20
        $ready | Should -BeTrue
    }

    It "Arrow key navigation moves through post list" {
        # After the multireddit load, focus is on postsListView (SetFocus).
        # Get cursor position before navigation
        $before = Get-TUICursorPosition -Name $script:session

        # Navigate down twice, then back up once
        Send-TUIKeys -Name $script:session -Keys "Down"
        Start-Sleep -Milliseconds 300
        Send-TUIKeys -Name $script:session -Keys "Down"
        Start-Sleep -Milliseconds 300
        Send-TUIKeys -Name $script:session -Keys "Up"
        Start-Sleep -Milliseconds 300

        # Verify the TUI is still showing the posts list (didn't crash or navigate away)
        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"
        $content | Should -Match "posts"

        # Cursor row should differ from initial position (Down moved the selection)
        $after = Get-TUICursorPosition -Name $script:session
        $after.Row | Should -Not -Be $before.Row
    }

    It "Navigate to post detail and close" {
        # After the arrow test, focus is on postsListView.
        # Press Enter to open the selected post detail dialog.
        Send-TUIKeys -Name $script:session -Keys "Enter"

        # Wait for the dialog to appear (title is always visible)
        $found = Wait-ForTUIText -Name $script:session -Text "Post Details" -TimeoutSeconds 20
        $found | Should -BeTrue

        # Close the dialog by navigating to the Close button and activating it.
        # The dialog has: contentView -> openBtn -> closeBtn in tab order.
        # Tab twice to reach closeBtn, Space to activate.
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Space"

        # Should return to the post list (Enter=view confirms we're back)
        $back = Wait-ForTUIText -Name $script:session -Text "Enter=view" -TimeoutSeconds 15
        $back | Should -BeTrue
    }

    It "Long post scrolling in detail dialog" {
        # Open a post detail dialog
        Send-TUIKeys -Name $script:session -Keys "Enter"

        $found = Wait-ForTUIText -Name $script:session -Text "Post Details" -TimeoutSeconds 20
        $found | Should -BeTrue

        # Send PageDown to scroll the content view
        Send-TUIKeys -Name $script:session -Keys "Pagedown"
        Start-Sleep -Milliseconds 500

        # Dialog should still be open (didn't crash from scrolling)
        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"
        # The dialog title or buttons should still be visible
        ($content -match "Close" -or $content -match "Post Details" -or $content -match "Open in Browser") | Should -BeTrue

        # Close via Tab-Tab-Space
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Space"

        $back = Wait-ForTUIText -Name $script:session -Text "Enter=view" -TimeoutSeconds 15
        $back | Should -BeTrue
    }

    It "Sort dropdown changes to new" {
        # Focus is on postsListView after dialog close.
        # Navigate to sortCombo (4 BTabs from postsListView).
        Focus-TUISortCombo -Name $script:session

        # Use dropdown navigation to select "new" (index 1).
        # Sort options: hot(0), new(1), top(2), rising(3).
        # F4 opens the dropdown, Down moves selection, Enter confirms.
        Send-TUIKeys -Name $script:session -Keys "F4"
        Start-Sleep -Milliseconds 300
        Send-TUIKeys -Name $script:session -Keys "Down"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Enter"
        Start-Sleep -Milliseconds 500

        # From sortCombo, BTab goes to loadBtn. Press Enter to trigger load.
        Send-TUIKeys -Name $script:session -Keys "BTab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Enter"

        # Wait for frame title to include "/new" (proves sort changed and load happened)
        $found = Wait-ForTUIText -Name $script:session -Text "/new" -TimeoutSeconds 20
        $found | Should -BeTrue
    }

    It "Time filter appears for top sort" {
        # Focus should be on postsListView after loadPosts SetFocus.
        # Navigate to sortCombo.
        Focus-TUISortCombo -Name $script:session

        # Current sort is "new" (index 1) from previous test.
        # Use dropdown to select "top" (index 2): F4, Down once, Enter.
        Send-TUIKeys -Name $script:session -Keys "F4"
        Start-Sleep -Milliseconds 300
        Send-TUIKeys -Name $script:session -Keys "Down"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Enter"
        Start-Sleep -Milliseconds 500

        # The "Time:" label should now be visible
        $found = Wait-ForTUIText -Name $script:session -Text "Time:" -TimeoutSeconds 10
        $found | Should -BeTrue

        # Now switch back to "hot": from "top" (index 2), F4, Up twice to "hot" (index 0), Enter.
        Send-TUIKeys -Name $script:session -Keys "F4"
        Start-Sleep -Milliseconds 300
        Send-TUIKeys -Name $script:session -Keys "Up"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Up"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Enter"
        Start-Sleep -Milliseconds 500

        # "Time:" label should disappear
        $gone = Wait-ForTUITextGone -Name $script:session -Text "Time:" -TimeoutSeconds 10
        $gone | Should -BeTrue

        # From sortCombo, BTab to loadBtn, Enter to reload with "hot" sort.
        Send-TUIKeys -Name $script:session -Keys "BTab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Enter"

        # Wait for "/hot" in frame title (proves load happened with correct sort)
        $loaded = Wait-ForTUIText -Name $script:session -Text "/hot" -TimeoutSeconds 20
        $loaded | Should -BeTrue
    }

    It "Search functionality returns results" {
        # Focus is on postsListView after loadPosts SetFocus.
        # Navigate to searchInput (3 BTabs from postsListView).
        Focus-TUISearchInput -Name $script:session

        # Clear any leftover text and type a search query
        Send-TUIKeys -Name $script:session -Keys "End"
        Start-Sleep -Milliseconds 100
        for ($i = 0; $i -lt 20; $i++) {
            Send-TUIKeys -Name $script:session -Keys "BSpace"
            Start-Sleep -Milliseconds 20
        }
        Send-TUIKeys -Name $script:session -Keys "powershell" -Literal
        Start-Sleep -Milliseconds 300

        # Tab to searchBtn and press Enter
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Enter"

        # Wait for search results to appear in the frame title
        $found = Wait-ForTUIText -Name $script:session -Text "results" -TimeoutSeconds 20
        $found | Should -BeTrue

        # Reset by reloading a normal subreddit to restore state.
        # searchPosts does NOT call SetFocus, so focus is still on searchBtn.
        # From searchBtn, navigate to postsListView: Tab -> searchGlobalCheck -> Tab -> postsListView
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        # Now on postsListView, use standard helper to reach subredditInput
        Focus-TUISubredditField -Name $script:session
        Set-TUISubreddit -Name $script:session -Subreddit "powershell"
        # Wait for "results" to disappear from the frame title (search title replaced by load title).
        # This avoids a race where "Enter=view" already exists in the old search results title.
        $titleChanged = Wait-ForTUITextGone -Name $script:session -Text "results" -TimeoutSeconds 20
        $titleChanged | Should -BeTrue
        # Now wait for the new subreddit title to fully load
        $loaded = Wait-ForTUIText -Name $script:session -Text "r/powershell/" -TimeoutSeconds 20
        $loaded | Should -BeTrue
    }

    It "Error handling for bad subreddit" {
        # Focus is on postsListView after loadPosts SetFocus.
        Focus-TUISubredditField -Name $script:session
        Set-TUISubreddit -Name $script:session -Subreddit "zzznotreal999qqq"

        # Wait for the response. Reddit may return 403/404 (error dialog) or 200 with
        # 0 posts, or even a valid listing. Wait long enough for the API round-trip.
        Start-Sleep -Seconds 5

        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"

        # The subreddit was submitted and the TUI handled it without crashing.
        # Accept any of: error dialog, error frame title, 0 posts, or even loaded posts.
        $handled = ($content -match "Error") -or
                   ($content -match "0 posts") -or
                   ($content -match "zzznotreal999qqq") -or
                   ($content -match "Enter=view")
        $handled | Should -BeTrue

        # Dismiss any error dialog with Enter (safe even if no dialog is showing)
        Send-TUIKeys -Name $script:session -Keys "Enter"
        Start-Sleep -Milliseconds 500

        # Recover by loading a valid subreddit.
        # Determine focus position to navigate safely to subredditInput.
        $screen2 = Get-TUIScreen -Name $script:session
        $content2 = $screen2 -join "`n"
        if ($content2 -match "\(Error\)") {
            # Error path: loadPosts threw, SetFocus was NOT called.
            # Focus returned to loadBtn after error dialog dismissed.
            # 1 BTab from loadBtn reaches subredditInput.
            Send-TUIKeys -Name $script:session -Keys "BTab"
            Start-Sleep -Milliseconds 200
        } else {
            # Success path (0 or more posts): loadPosts completed, SetFocus called on postsListView.
            Focus-TUISubredditField -Name $script:session
        }
        Set-TUISubreddit -Name $script:session -Subreddit "powershell"
        # Wait for the bad subreddit to disappear from the frame title
        $recovered = Wait-ForTUITextGone -Name $script:session -Text "zzznotreal999qqq" -TimeoutSeconds 20
        $recovered | Should -BeTrue
        $loaded = Wait-ForTUIText -Name $script:session -Text "r/powershell/" -TimeoutSeconds 20
        $loaded | Should -BeTrue
    }

    It "Favorites add and remove via TUI" {
        # Focus is on postsListView after loadPosts SetFocus.
        # The current subreddit is "powershell" (loaded in previous test).

        # Determine if loadMoreBtn is visible (affects tab count)
        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"
        $loadMoreVisible = $content -match "Load More"

        # Tab order from postsListView forward wraps to favoritesFrame:
        # If loadMoreBtn visible: postsListView -> loadMoreBtn -> favoritesList -> addFavBtn (3 Tabs)
        # If loadMoreBtn hidden:  postsListView -> favoritesList -> addFavBtn (2 Tabs)
        $tabsToAddBtn = if ($loadMoreVisible) { 3 } else { 2 }

        for ($i = 0; $i -lt $tabsToAddBtn; $i++) {
            Send-TUIKeys -Name $script:session -Keys "Tab"
            Start-Sleep -Milliseconds 200
        }

        # Press Space on addFavBtn to add the current subreddit (from subredditInput)
        Send-TUIKeys -Name $script:session -Keys "Space"
        Start-Sleep -Milliseconds 500

        # Capture the favorites sidebar (left 25 columns) to verify add worked.
        # Use "r/powershell\s" to match exactly "r/powershell" (with trailing space),
        # avoiding false positives from entries like "r/powershell+sysadmin".
        $screenAfter = Get-TUIScreen -Name $script:session
        $favsAfter = ($screenAfter | ForEach-Object { if ($_.Length -ge 25) { $_.Substring(0, 25) } else { $_ } }) -join "`n"
        $favsAfter | Should -Match "r/powershell\s"

        # Now remove it. From addFavBtn, BTab goes to favoritesList.
        Send-TUIKeys -Name $script:session -Keys "BTab"
        Start-Sleep -Milliseconds 200

        # Select the last entry (should be "powershell" since it was just added)
        Send-TUIKeys -Name $script:session -Keys "End"
        Start-Sleep -Milliseconds 200

        # Forward Tab from favoritesList -> addFavBtn -> removeFavBtn (2 Tabs)
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200
        Send-TUIKeys -Name $script:session -Keys "Tab"
        Start-Sleep -Milliseconds 200

        # Press Space to remove the selected favorite
        Send-TUIKeys -Name $script:session -Keys "Space"
        Start-Sleep -Milliseconds 500

        # Verify the favorites sidebar no longer has "r/powershell" (exactly)
        $screenFinal = Get-TUIScreen -Name $script:session
        $favsFinal = ($screenFinal | ForEach-Object { if ($_.Length -ge 25) { $_.Substring(0, 25) } else { $_ } }) -join "`n"
        $favsFinal | Should -Not -Match "r/powershell\s"

        # Navigate back to postsListView for subsequent tests.
        # From removeFavBtn, forward Tabs: removeFavBtn -> subredditInput -> loadBtn ->
        # sortCombo -> searchInput -> searchBtn -> searchGlobalCheck -> postsListView (7 Tabs)
        for ($i = 0; $i -lt 7; $i++) {
            Send-TUIKeys -Name $script:session -Keys "Tab"
            Start-Sleep -Milliseconds 100
        }
    }

    It "O key handler does not crash TUI" {
        # Focus should be on or near postsListView.
        # Send the "o" key which triggers the Open in Browser handler.
        # The handler calls Start-Process which may fail silently in tmux
        # (no display), but the TUI should remain stable.
        Send-TUIKeys -Name $script:session -Keys "o" -Literal
        Start-Sleep -Milliseconds 500

        # Verify TUI is still running and showing the status bar and frame
        $screen = Get-TUIScreen -Name $script:session
        $content = $screen -join "`n"
        $content | Should -Match "Open"
        $content | Should -Match "Enter=view"
    }

    It "Load More button is enabled after initial load" {
        # The Load More button is positioned at AnchorEnd(1) in the content frame.
        # After the fix, it should be visible on screen. But visibility depends on
        # whether there are more posts to load (pagination cursor).
        # Check the module debug log for the Load More button state.
        $logFile = Join-Path ([System.IO.Path]::GetTempPath()) "psreddittui-debug.log"
        $logContent = Get-Content $logFile -Tail 100
        $hasMoreEntry = $logContent | Where-Object { $_ -match "showing Load More button=True" }
        $hasMoreEntry | Should -Not -BeNullOrEmpty
    }

    It "Ctrl+Q quits the TUI" {
        # Send Ctrl+Q to quit
        Send-TUIKeys -Name $script:session -Keys "C-q"

        # Give the process time to exit
        Start-Sleep -Seconds 2

        # Verify the tmux session no longer exists
        $sessions = tmux list-sessions 2>&1
        $stillRunning = $sessions | Where-Object { $_ -match $script:session }
        $stillRunning | Should -BeNullOrEmpty
    }
}
