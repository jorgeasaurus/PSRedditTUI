# PSRedditTUI

[![CI/CD Pipeline](https://github.com/jorgeasaurus/PSRedditTUI/actions/workflows/ci.yml/badge.svg)](https://github.com/jorgeasaurus/PSRedditTUI/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/PSRedditTUI)](https://www.powershellgallery.com/packages/PSRedditTUI)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)](https://github.com/jorgeasaurus/PSRedditTUI)

A PowerShell module for browsing Reddit in a Terminal UI (TUI)

![PSRedditTUI MainUI Screenshot](./media/MainUI.png)
![PSRedditTUI Comments Screenshot](./media/comments.png)

## Features

- 🖥️ **Terminal User Interface**: Built with Terminal.Gui for an interactive console experience
- ⭐ **Favorites Sidebar**: Manage your favorite subreddits with easy add/remove functionality
- 🔍 **Search**: Search within subreddits or across all of Reddit
- 📊 **Sort & Filter**: Browse by hot, new, top, or rising with time filters (day/week/month/year/all)
- 💬 **View Comments**: Read post content and comments directly in the terminal
- 🌐 **Open in Browser**: Press `O` to open any post in your default browser
- 📝 **Comprehensive Logging**: Built-in logging for debugging and troubleshooting
- 🚀 **Reddit JSON API**: No authentication required for public subreddits
- 🔄 **Cross-Platform**: Works on Windows, macOS, and Linux with PowerShell 7+

## Requirements

- PowerShell Core 7.0 or higher
- Terminal.Gui .NET library

## Installation

### From PowerShell Gallery (Recommended)

```powershell
# Install the module
Install-Module -Name PSRedditTUI -Scope CurrentUser

# Import and run
Import-Module PSRedditTUI
Install-PSRedditTUITerminalGui  # First time only - installs Terminal.Gui dependency
Show-RedditTUI
```

### From Source

1. Clone the repository:

```powershell
git clone https://github.com/jorgeasaurus/PSRedditTUI.git
cd PSRedditTUI
```

2. Install Terminal.Gui dependency:

```powershell
Import-Module ./PSRedditTUI.psd1
Install-PSRedditTUITerminalGui
```

3. Import and run:

```powershell
Import-Module ./PSRedditTUI.psd1
Show-RedditTUI
```

## Usage

### Launch the Terminal UI

```powershell
# Start with default subreddit (popular)
Show-RedditTUI

# Start with a specific subreddit
Show-RedditTUI -InitialSubreddit "powershell"
```

### Terminal UI Controls

| Key | Action |
|-----|--------|
| ↑/↓ | Navigate through posts and favorites |
| Enter | View post details and comments |
| O | Open current post in browser |
| Tab | Switch between UI elements |
| Ctrl+Q | Quit the application |
| ESC | Close dialogs |

### UI Elements

- **Subreddit Input**: Enter any subreddit name and click "Load"
- **Sort Dropdown**: Select hot, new, top, or rising
- **Time Filter**: When sorting by "top", filter by day/week/month/year/all
- **Search**: Enter a search query and click "Search" (searches current subreddit) or "Global" (searches all of Reddit)
- **Favorites List**: Quick access to your saved subreddits

### Managing Favorites

#### In the Terminal UI:
1. Enter a subreddit name in the input field
2. Click "+" to add it to favorites
3. Select a favorite and click "-" to remove it

#### From PowerShell:

```powershell
# Add a favorite subreddit
Add-Favorite -Subreddit "powershell"

# Remove a favorite subreddit
Remove-Favorite -Subreddit "powershell"

# View all favorites
Get-Favorites
```

### Fetch Reddit Data Programmatically

```powershell
# Get posts from a subreddit
$posts = Get-RedditPosts -Subreddit "powershell" -Sort "hot"

# Get top posts from the last month
$posts = Get-RedditPosts -Subreddit "sysadmin" -Sort "top" -Time "month"

# Get comments for a post
$comments = Get-RedditComments -Permalink "/r/powershell/comments/abc123/post_title/"

# Search within a subreddit
$results = Search-Reddit -Query "automation" -Subreddit "powershell"

# Search all of Reddit
$results = Search-Reddit -Query "terminal ui" -Sort "relevance"

# Display post information
$posts | Select-Object Title, Score, NumComments, Author | Format-Table
```

### Logging

```powershell
# View recent log entries
Get-PSRedditTUILog -Tail 20

# Set log level (Debug, Info, Warning, Error)
Set-PSRedditTUILogLevel -Level Debug

# Clear log file
Clear-PSRedditTUILog
```

## How It Works

PSRedditTUI uses Reddit's JSON API by appending `.json` to Reddit URLs. This allows the module to fetch data without requiring authentication for public subreddits.

Example:
- URL: `https://www.reddit.com/r/powershell/top?t=month`
- Becomes: `https://www.reddit.com/r/powershell/top.json?t=month`

## Favorites Storage

Favorites are stored locally in `~/.psreddittui_favorites.json` and persist between sessions.

## Exported Functions

| Function | Description |
|----------|-------------|
| `Show-RedditTUI` | Launch the Terminal UI browser |
| `Get-RedditData` | Fetch raw data from Reddit JSON API |
| `Get-RedditPosts` | Get posts from a subreddit with sorting options |
| `Get-RedditComments` | Get comments for a specific post |
| `Search-Reddit` | Search within a subreddit or all of Reddit |
| `Get-Favorites` | Load favorites from local storage |
| `Add-Favorite` | Add a subreddit to favorites |
| `Remove-Favorite` | Remove a subreddit from favorites |
| `Install-PSRedditTUITerminalGui` | Install Terminal.Gui dependency from NuGet |
| `Get-PSRedditTUILog` | View log entries |
| `Set-PSRedditTUILogLevel` | Set logging verbosity |
| `Clear-PSRedditTUILog` | Clear the log file |

## Building from Source

```powershell
# Install build dependencies and run full CI pipeline
./build.ps1 -Task CI

# Run only tests
./build.ps1 -Task Test

# Run only static analysis
./build.ps1 -Task Analyze

# Build module for distribution
./build.ps1 -Task Build
```

## Troubleshooting

### Terminal.Gui not found

Run the installer function:

```powershell
Install-PSRedditTUITerminalGui
```

Or use the deprecated script (for backwards compatibility):

```powershell
./Install-TerminalGui.ps1
```

### PowerShell version

This module requires PowerShell Core 7+. Check your version:

```powershell
$PSVersionTable.PSVersion
```

If you're using Windows PowerShell 5.1, install PowerShell 7:
- Download from: https://github.com/PowerShell/PowerShell/releases

### View debug logs

```powershell
Set-PSRedditTUILogLevel -Level Debug
Show-RedditTUI
Get-PSRedditTUILog -Tail 50
```

## License

This project is open source.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

### Development

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `./build.ps1 -Task CI` to verify tests pass
5. Submit a pull request
