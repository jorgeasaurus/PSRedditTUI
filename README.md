# PSRedditTUI
A PowerShell module for browsing Reddit in a Terminal UI (TUI)

## Features

- 🚀 **Reddit JSON API Integration**: Automatically appends `/.json` to Reddit URLs for efficient data fetching
- 🖥️ **Terminal User Interface**: Built with Terminal.Gui (ConsoleGui) for an interactive console experience
- ⭐ **Favorites Sidebar**: Manage your favorite subreddits with easy add/remove functionality
- 🔄 **PowerShell Core Only**: Designed for PowerShell 7+ (pwsh)
- 📊 **Subreddit Browser**: View posts with scores, comments, and titles
- 🎯 **Multiple Sorting Options**: Browse by hot, new, top, or rising posts

## Requirements

- PowerShell Core 7.0 or higher
- Terminal.Gui module

## Installation

### Install Terminal.Gui dependency

```powershell
Install-Module -Name Terminal.Gui -Scope CurrentUser
```

### Install PSRedditTUI

1. Clone or download this repository
2. Import the module:

```powershell
Import-Module ./PSRedditTUI.psd1
```

Or install it in your PowerShell modules directory:

```powershell
# Copy to your PowerShell modules directory
$modulePath = "$HOME/.local/share/powershell/Modules/PSRedditTUI"
New-Item -ItemType Directory -Path $modulePath -Force
Copy-Item PSRedditTUI.* $modulePath/
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

- **Arrow Keys**: Navigate through posts and favorites
- **Enter**: Select a subreddit from favorites
- **Tab**: Switch between UI elements
- **Ctrl+Q** or **ESC**: Quit the application
- **F1**: Show help dialog

### Managing Favorites

#### In the Terminal UI:
1. Enter a subreddit name in the input field
2. Click "Add" to add it to favorites
3. Select a favorite and click "Remove" to remove it

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
# Get data from any Reddit URL (/.json is automatically appended)
$data = Get-RedditData -Url "https://www.reddit.com/r/powershell"

# Get posts from a subreddit
$posts = Get-RedditPosts -Subreddit "powershell" -Sort "hot"

# Display post information
$posts | Select-Object Title, Score, Comments, Author
```

## How It Works

PSRedditTUI uses Reddit's JSON API by appending `/.json` to any Reddit URL. This allows the module to fetch data without requiring authentication for public subreddits.

Example:
- URL: `https://www.reddit.com/r/powershell`
- Becomes: `https://www.reddit.com/r/powershell/.json`

The module then parses the JSON response and displays it in an interactive Terminal UI built with Terminal.Gui.

## Favorites Storage

Favorites are stored locally in `~/.psreddittui_favorites.json` and persist between sessions.

## Screenshots

The Terminal UI features:
- Left sidebar with favorite subreddits
- Main content area for browsing posts
- Post information including scores (↑) and comment counts (💬)
- Input field for entering any subreddit
- Menu bar and status bar with keyboard shortcuts

## Functions

### Exported Functions

- `Show-RedditTUI`: Launch the Terminal UI browser
- `Get-RedditData`: Fetch data from Reddit JSON API
- `Get-RedditPosts`: Get posts from a specific subreddit
- `Get-Favorites`: Load favorites from local storage
- `Add-Favorite`: Add a subreddit to favorites
- `Remove-Favorite`: Remove a subreddit from favorites

## Troubleshooting

### Terminal.Gui not found

If you get an error about Terminal.Gui not being available:

```powershell
Install-Module -Name Terminal.Gui -Scope CurrentUser
```

### PowerShell version

This module requires PowerShell Core 7+. Check your version:

```powershell
$PSVersionTable.PSVersion
```

If you're using Windows PowerShell 5.1, install PowerShell 7:
- Download from: https://github.com/PowerShell/PowerShell/releases

## License

This project is open source.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
