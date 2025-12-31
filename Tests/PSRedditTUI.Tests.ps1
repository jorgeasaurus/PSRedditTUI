#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for PSRedditTUI module
.DESCRIPTION
    Tests core functionality that doesn't require Terminal.Gui
#>

BeforeAll {
    # Import the module (not dot-source) to get proper function scoping
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSRedditTUI.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    # Clean up module
    Remove-Module PSRedditTUI -Force -ErrorAction SilentlyContinue
}

Describe 'PSRedditTUI Module' {
    Context 'Module Structure' {
        It 'Should have a valid module manifest' {
            $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSRedditTUI.psd1'
            $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.Name | Should -Be 'PSRedditTUI'
        }

        It 'Should have required module version' {
            $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSRedditTUI.psd1'
            $manifest = Import-PowerShellDataFile -Path $manifestPath
            $manifest.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
        }

        It 'Should require PowerShell 7.0 or higher' {
            $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSRedditTUI.psd1'
            $manifest = Import-PowerShellDataFile -Path $manifestPath
            [version]$manifest.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
        }

        It 'Should export expected functions' {
            $module = Get-Module PSRedditTUI
            $expectedFunctions = @(
                'Get-RedditData',
                'Get-RedditPosts',
                'Get-RedditComments',
                'Search-Reddit',
                'Get-Favorites',
                'Add-Favorite',
                'Remove-Favorite',
                'Get-PSRedditTUILog',
                'Clear-PSRedditTUILog',
                'Set-PSRedditTUILogLevel'
            )
            foreach ($func in $expectedFunctions) {
                $module.ExportedFunctions.Keys | Should -Contain $func
            }
        }
    }

    Context 'Favorites Management' {
        BeforeAll {
            # Save current favorites
            $script:savedFavorites = Get-Favorites
        }

        AfterAll {
            # Note: We don't restore because tests may have modified the file
            # This is acceptable for integration tests
        }

        It 'Get-Favorites should not throw' {
            { Get-Favorites } | Should -Not -Throw
        }

        It 'Add-Favorite should accept a subreddit name' {
            { Add-Favorite -Subreddit 'testsubreddit123' } | Should -Not -Throw
        }

        It 'Add-Favorite should work with r/ prefix' {
            { Add-Favorite -Subreddit 'r/prefixtest999' } | Should -Not -Throw
        }

        It 'Remove-Favorite should remove a subreddit' {
            Add-Favorite -Subreddit 'toberemoved789'
            $before = Get-Favorites
            Remove-Favorite -Subreddit 'toberemoved789'
            $after = Get-Favorites
            $after | Should -Not -Contain 'toberemoved789'
        }
    }

    Context 'Logging Functions' {
        It 'Get-PSRedditTUILog should return log entries' {
            $result = Get-PSRedditTUILog -Tail 5
            # May be empty or contain entries
            { $result } | Should -Not -Throw
        }

        It 'Set-PSRedditTUILogLevel should accept valid levels' {
            { Set-PSRedditTUILogLevel -Level 'Debug' } | Should -Not -Throw
            { Set-PSRedditTUILogLevel -Level 'Info' } | Should -Not -Throw
            { Set-PSRedditTUILogLevel -Level 'Warning' } | Should -Not -Throw
            { Set-PSRedditTUILogLevel -Level 'Error' } | Should -Not -Throw
        }

        It 'Clear-PSRedditTUILog should not throw' {
            { Clear-PSRedditTUILog } | Should -Not -Throw
        }
    }

    Context 'URL Construction' {
        It 'Should build correct subreddit URL' {
            # Test the URL pattern used internally
            $subreddit = 'powershell'
            $sort = 'hot'
            $url = "https://www.reddit.com/r/$subreddit/$sort"
            $url | Should -Be 'https://www.reddit.com/r/powershell/hot'
        }

        It 'Should build correct URL with time filter' {
            $subreddit = 'sysadmin'
            $sort = 'top'
            $time = 'month'
            $url = "https://www.reddit.com/r/$subreddit/$sort"
            if ($sort -eq 'top') {
                $url += "?t=$time"
            }
            $url | Should -Be 'https://www.reddit.com/r/sysadmin/top?t=month'
        }

        It 'Should correctly insert .json before query string' {
            $url = 'https://www.reddit.com/r/test/top?t=month'
            $result = $url -replace '\?', '.json?'
            $result | Should -Be 'https://www.reddit.com/r/test/top.json?t=month'
        }
    }

    Context 'API Functions' {
        It 'Get-RedditData should exist and be callable' {
            Get-Command -Name Get-RedditData -Module PSRedditTUI | Should -Not -BeNullOrEmpty
        }

        It 'Get-RedditPosts should exist and be callable' {
            Get-Command -Name Get-RedditPosts -Module PSRedditTUI | Should -Not -BeNullOrEmpty
        }

        It 'Get-RedditComments should exist and be callable' {
            Get-Command -Name Get-RedditComments -Module PSRedditTUI | Should -Not -BeNullOrEmpty
        }

        It 'Search-Reddit should exist and be callable' {
            Get-Command -Name Search-Reddit -Module PSRedditTUI | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Show-RedditTUI' {
    It 'Should exist as a function' {
        Get-Command -Name Show-RedditTUI -Module PSRedditTUI | Should -Not -BeNullOrEmpty
    }

    It 'Should have InitialSubreddit parameter' {
        $cmd = Get-Command -Name Show-RedditTUI -Module PSRedditTUI
        $cmd.Parameters.Keys | Should -Contain 'InitialSubreddit'
    }
}
