# PSRedditTUI - Copilot Instructions

## Build, Test, and Lint

```powershell
# Bootstrap dependencies (InvokeBuild, Pester 5, PSScriptAnalyzer)
./build.ps1

# Full CI pipeline (analyze + test + build)
./build.ps1 -Task CI

# Individual tasks
./build.ps1 -Task Analyze    # PSScriptAnalyzer (errors + warnings, excludes PSAvoidUsingWriteHost)
./build.ps1 -Task Test       # Pester tests
./build.ps1 -Task Build      # Build to ./build/PSRedditTUI/

# Run a single test by name
$config = New-PesterConfiguration
$config.Run.Path = './Tests'
$config.Filter.FullName = '*Favorites Management*'
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

The build system uses **InvokeBuild** (`PSRedditTUI.build.ps1`) bootstrapped by `build.ps1`. Build output goes to `./build/PSRedditTUI/`.

## Architecture

This is a **single-file PowerShell module** — all code lives in `PSRedditTUI.psm1` (~1925 lines), organized by `#region` blocks:

| Region | Purpose |
|--------|---------|
| Logging | `Write-Log` internal logger → `~/.psreddittui.log` |
| Reddit API Functions | `Get-RedditData`, `Get-RedditPosts`, `Get-RedditComments`, `Search-Reddit` |
| Favorites Management | `Get-Favorites`, `Add-Favorite`, `Remove-Favorite`, `Save-Favorites` (private) |
| Helper Functions | Currently empty; `ConvertTo-CommentObject` lives in Reddit API region |
| Terminal UI | `Show-RedditTUI` — the main TUI entry point built on Terminal.Gui v1 |
| Dependency Management | `Install-PSRedditTUITerminalGui` — NuGet package installer |

**Data flow:** `Get-RedditData` appends `.json` to standard Reddit URLs (no authentication), with a fallback from `Invoke-WebRequest` to `Invoke-RestMethod` for a known PowerShell Core Unicode bug.

**Dependencies:** Terminal.Gui v1.16.0 and NStack.Core install to `~/.psreddittui-packages/` via `Install-PSRedditTUITerminalGui` and auto-load at module import. The loader resolves DLLs across `net8.0` → `net7.0` → `netstandard2.1` target folders. Terminal.Gui v2.x is not supported.

**State files** (user home):
- `~/.psreddittui_favorites.json` — subreddit favorites
- `~/.psreddittui.log` — log file
- `~/.psreddittui-packages/` — Terminal.Gui and NStack DLLs

## Conventions

- **PowerShell 7+ only** (`CompatiblePSEditions = 'Core'`). No Windows PowerShell 5.1 support.
- All public functions use `[CmdletBinding()]` with comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).
- Error handling currently uses `throw` / `Write-Error` throughout. The preferred pattern for new code is `$PSCmdlet.ThrowTerminatingError()` / `$PSCmdlet.WriteError()` with constructed `ErrorRecord` objects (per `.github/instructions/powershell.instructions.md`).
- `Write-Log` for all internal logging. `Write-Host` is used in some user-facing paths; `PSAvoidUsingWriteHost` is intentionally excluded from analysis.
- Module version is read dynamically from the manifest (`$MyInvocation.MyCommand.Module.Version`), not hardcoded.
- `Add-Favorite` and `Remove-Favorite` support `-PassThru` for pipeline chaining.
- `Get-RedditPosts` validates subreddit names with `ValidatePattern`; other functions that accept subreddit names do not currently enforce validation.
- Tests import via `Import-Module` (not dot-sourcing), verify exported function metadata, and pass without Terminal.Gui loaded.
- ⚠️ **Tests mutate `~/.psreddittui_favorites.json`** — the Pester suite writes to the real favorites file without restoring it. Back up or override `$HOME` when running tests locally.
- Publishing is triggered by pushing a `v*.*.*` git tag. The CI validates the tag matches `ModuleVersion` in the manifest before publishing to PSGallery.
