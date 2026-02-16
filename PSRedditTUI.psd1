@{
    # Module manifest for module 'PSRedditTUI'
    RootModule = 'PSRedditTUI.psm1'
    
    # Version number of this module.
    ModuleVersion = '0.1.2'
    
    # Supported PSEditions
    CompatiblePSEditions = @('Core')
    
    # ID used to uniquely identify this module
    GUID = 'a8f7e3d2-1b4c-4d6e-9f2a-7c8b5e3d1a0f'
    
    # Author of this module
    Author = 'Jorgeasaurus'
    
    # Company or vendor of this module
    CompanyName = 'Jorgeasaurus'
    
    # Copyright statement for this module
    Copyright = '(c) 2025 Jorgeasaurus. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'A PowerShell module for browsing Reddit in a Terminal UI using ConsoleGui tools. Features include subreddit browsing, favorites management, and JSON API integration.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'
    
    # Functions to export from this module
    FunctionsToExport = @(
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
    
    # Cmdlets to export from this module
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module
    AliasesToExport = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Reddit', 'TUI', 'Terminal', 'Console', 'GUI', 'PSCore')
            
            # A URL to the license for this module.
            LicenseUri = ''
            
            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/jorgeasaurus/PSRedditTUI'
            
            # ReleaseNotes of this module
            ReleaseNotes = @'
## Version 0.1.2
- Code quality improvements following PowerShell best practices
- Removed Write-ErrorLog wrapper function (simplified to Write-Log -Level Error)
- Removed Open-UrlInBrowser function (simplified to native Start-Process)
- Added [CmdletBinding()] to Write-Log for proper cmdlet support
- Added -PassThru pattern to Add-Favorite and Remove-Favorite functions
- Fixed hardcoded version string (now uses dynamic module version)
- Fixed subreddit validation pattern to allow dashes in names
- Removed Write-Host usage in error handling (replaced with proper exceptions)
- Removed module load logging noise
- Reduced codebase by ~82 lines while improving maintainability
'@
        }
    }
}
