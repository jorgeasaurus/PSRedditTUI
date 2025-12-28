#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Example script demonstrating PSRedditTUI module usage
.DESCRIPTION
    This script shows how to use the PSRedditTUI module to interact with Reddit
    programmatically and launch the Terminal UI.
#>

# Import the module
Import-Module ./PSRedditTUI.psd1 -Force

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "PSRedditTUI - Example Usage" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Example 1: Managing favorites
Write-Host "Example 1: Managing Favorites" -ForegroundColor Yellow
Write-Host "------------------------------"
Write-Host "Adding some favorite subreddits..."
Add-Favorite -Subreddit "powershell"
Add-Favorite -Subreddit "programming"
Add-Favorite -Subreddit "linux"
Add-Favorite -Subreddit "sysadmin"

Write-Host ""
Write-Host "Current favorites:" -ForegroundColor Green
$favorites = Get-Favorites
$favorites | ForEach-Object { Write-Host "  - r/$_" }

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Example 2: Demonstrate URL transformation
Write-Host ""
Write-Host "Example 2: Reddit JSON API URL Transformation" -ForegroundColor Yellow
Write-Host "----------------------------------------------"
$exampleUrls = @(
    "https://www.reddit.com/r/powershell",
    "https://www.reddit.com/r/programming/hot"
)

foreach ($url in $exampleUrls) {
    Write-Host "Original: $url" -ForegroundColor White
    # The module automatically appends /.json
    $jsonUrl = if ($url.EndsWith('.json')) { $url } else { $url.TrimEnd('/') + '/.json' }
    Write-Host "API URL:  $jsonUrl" -ForegroundColor Green
    Write-Host ""
}

Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Example 3: Launch the TUI (commented out by default)
Write-Host ""
Write-Host "Example 3: Launching Terminal UI" -ForegroundColor Yellow
Write-Host "---------------------------------"
Write-Host "To launch the Terminal UI, uncomment the line below:"
Write-Host "  # Show-RedditTUI -InitialSubreddit 'powershell'" -ForegroundColor Gray
Write-Host ""
Write-Host "Or run it directly from PowerShell:"
Write-Host "  Show-RedditTUI" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: Terminal.Gui must be installed first (from NuGet):" -ForegroundColor Yellow
Write-Host "  Install-Package -Name Terminal.Gui -ProviderName NuGet -Scope CurrentUser" -ForegroundColor Cyan
Write-Host ""

# Uncomment to launch the TUI:
# Show-RedditTUI -InitialSubreddit "powershell"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Example completed!" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Cyan
