#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for PSRedditTUI module
.DESCRIPTION
    Tests core functionality that doesn't require Terminal.Gui.
    Network calls are mocked; favorites, auth and log files are redirected to TestDrive
    so the user's real files under $HOME are never touched.
#>

BeforeAll {
    # Import the module (not dot-source) to get proper function scoping
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSRedditTUI.psd1'
    Import-Module $modulePath -Force

    # Keep real credentials in the environment from leaking into tests
    $script:savedEnv = @{}
    foreach ($name in 'PSREDDITTUI_CLIENT_ID', 'PSREDDITTUI_CLIENT_SECRET', 'PSREDDITTUI_USERNAME') {
        $script:savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $null)
    }

    # The module loaded the real favorites at import, so reset state as well as paths
    InModuleScope PSRedditTUI -Parameters @{ Root = $TestDrive } {
        param($Root)
        $script:FavoritesFile = Join-Path $Root 'favorites.json'
        $script:AuthFile = Join-Path $Root 'auth.json'
        $script:LogFile = Join-Path $Root 'debug.log'
        $script:Favorites = @()
        $script:AccessToken = $null
        $script:AccessTokenExpiry = [datetime]::MinValue
    }

    function New-FakeWebResponse {
        param(
            [int]$StatusCode = 200,
            [string]$Content = '{}',
            [string]$ContentType = 'application/json; charset=UTF-8',
            [hashtable]$ExtraHeaders = @{}
        )
        $headers = @{ 'Content-Type' = $ContentType } + $ExtraHeaders
        [PSCustomObject]@{ StatusCode = $StatusCode; Content = $Content; Headers = $headers }
    }

    $script:listingJson = @'
{
  "kind": "Listing",
  "data": {
    "after": "t3_next",
    "children": [
      { "kind": "t3", "data": { "title": "Tips & tricks <2026>", "author": "alice", "score": 42, "subreddit": "PowerShell",
        "permalink": "/r/PowerShell/comments/abc/tips/", "num_comments": 3, "created_utc": 1700000000.0,
        "selftext": "body", "is_self": true, "url": "https://www.reddit.com/r/PowerShell/comments/abc/tips/",
        "post_hint": "self", "is_video": false } },
      { "kind": "t3", "data": { "title": "A link", "author": "bob", "score": 7, "subreddit": "PowerShell",
        "permalink": "/r/PowerShell/comments/def/link/", "num_comments": 0, "created_utc": 1700000100,
        "selftext": "", "is_self": false, "url": "https://example.com/article",
        "post_hint": "link", "is_video": false } }
    ]
  }
}
'@
}

AfterAll {
    foreach ($name in $script:savedEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:savedEnv[$name])
    }
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
                'Set-PSRedditTUILogLevel',
                'Install-PSRedditTUITerminalGui',
                'Set-RedditCredential',
                'Remove-RedditCredential'
            )
            foreach ($func in $expectedFunctions) {
                $module.ExportedFunctions.Keys | Should -Contain $func
            }
        }
    }

    Context 'Favorites Management' {
        It 'Get-Favorites should create defaults on first launch' {
            $favorites = Get-Favorites
            $favorites | Should -Contain 'powershell'
            Join-Path $TestDrive 'favorites.json' | Should -Exist
        }

        It 'Add-Favorite should normalize case and strip the r/ prefix' {
            Add-Favorite -Subreddit 'r/PrefixTest999'
            $favorites = Get-Favorites
            $favorites | Should -Contain 'prefixtest999'
        }

        It 'Add-Favorite should report duplicates' {
            Add-Favorite -Subreddit 'dupetest'
            (Add-Favorite -Subreddit 'DupeTest' -PassThru).Action | Should -Be 'AlreadyExists'
        }

        It 'Remove-Favorite should remove a subreddit' {
            Add-Favorite -Subreddit 'toberemoved789'
            Remove-Favorite -Subreddit 'toberemoved789'
            $favorites = Get-Favorites
            $favorites | Should -Not -Contain 'toberemoved789'
        }

        It 'Should never write to the real favorites file' {
            InModuleScope PSRedditTUI { $script:FavoritesFile } | Should -BeLike "$TestDrive*"
        }
    }

    Context 'Logging Functions' {
        It 'Get-PSRedditTUILog should return log entries' {
            { Get-PSRedditTUILog -Tail 5 } | Should -Not -Throw
        }

        It 'Set-PSRedditTUILogLevel should accept valid levels' {
            { Set-PSRedditTUILogLevel -Level 'Debug' } | Should -Not -Throw
            { Set-PSRedditTUILogLevel -Level 'Info' } | Should -Not -Throw
            { Set-PSRedditTUILogLevel -Level 'Warning' } | Should -Not -Throw
            { Set-PSRedditTUILogLevel -Level 'Error' } | Should -Not -Throw
            Set-PSRedditTUILogLevel -Level 'Debug'
        }

        It 'Clear-PSRedditTUILog should not throw' {
            { Clear-PSRedditTUILog } | Should -Not -Throw
        }
    }

    Context 'Get-RedditData (unauthenticated)' {
        BeforeEach {
            Mock -ModuleName PSRedditTUI Invoke-WebRequest { New-FakeWebResponse -Content $script:listingJson }
        }

        It 'Should append .json and raw_json=1 to a plain URL' {
            Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot' | Out-Null
            Should -Invoke -ModuleName PSRedditTUI Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://www.reddit.com/r/powershell/hot.json?raw_json=1'
            }
        }

        It 'Should insert .json before an existing query string' {
            Get-RedditData -Url 'https://www.reddit.com/r/test/top?t=month' | Out-Null
            Should -Invoke -ModuleName PSRedditTUI Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://www.reddit.com/r/test/top.json?t=month&raw_json=1'
            }
        }

        It 'Should send a User-Agent in platform:app:version format' {
            Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot' | Out-Null
            Should -Invoke -ModuleName PSRedditTUI Invoke-WebRequest -Times 1 -ParameterFilter {
                $UserAgent -match '^(windows|macos|linux):PSRedditTUI:v\d+\.\d+\.\d+ \(.+\)$'
            }
        }

        It 'Should explain how to fix an HTML 403 block' {
            Mock -ModuleName PSRedditTUI Invoke-WebRequest {
                New-FakeWebResponse -StatusCode 403 -Content '<html>blocked</html>' -ContentType 'text/html'
            }
            { Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot' -ErrorAction Stop } |
                Should -Throw '*Set-RedditCredential*'
        }

        It 'Should report a JSON 403 as a private subreddit' {
            Mock -ModuleName PSRedditTUI Invoke-WebRequest {
                New-FakeWebResponse -StatusCode 403 -Content '{"reason":"private"}'
            }
            { Get-RedditData -Url 'https://www.reddit.com/r/secret/hot' -ErrorAction Stop } |
                Should -Throw '*private*'
        }

        It 'Should retry once after a 429' {
            $state = @{ Calls = 0 }
            Mock -ModuleName PSRedditTUI Start-Sleep { }
            Mock -ModuleName PSRedditTUI Invoke-WebRequest {
                $state.Calls++
                if ($state.Calls -eq 1) {
                    New-FakeWebResponse -StatusCode 429 -Content '{}' -ExtraHeaders @{ 'Retry-After' = '2' }
                } else {
                    New-FakeWebResponse -Content $script:listingJson
                }
            }
            $result = Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot'
            $result.data.after | Should -Be 't3_next'
            Should -Invoke -ModuleName PSRedditTUI Invoke-WebRequest -Times 2 -Exactly
            Should -Invoke -ModuleName PSRedditTUI Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
        }
    }

    Context 'Get-RedditData (OAuth)' {
        BeforeAll {
            Set-RedditCredential -ClientId 'test-client-id' -Username 'tester'
        }

        AfterAll {
            Remove-RedditCredential
        }

        BeforeEach {
            InModuleScope PSRedditTUI { $script:AccessToken = $null }
            Mock -ModuleName PSRedditTUI Invoke-RestMethod {
                [PSCustomObject]@{ access_token = 'tok123'; expires_in = 86400 }
            } -ParameterFilter { $Uri -like '*api/v1/access_token' }
            Mock -ModuleName PSRedditTUI Invoke-WebRequest { New-FakeWebResponse -Content $script:listingJson }
        }

        It 'Should save the client ID to the redirected auth file' {
            Join-Path $TestDrive 'auth.json' | Should -Exist
        }

        It 'Should call oauth.reddit.com with a bearer token and no .json suffix' {
            Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot' | Out-Null
            Should -Invoke -ModuleName PSRedditTUI Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://oauth.reddit.com/r/powershell/hot?raw_json=1' -and
                $Headers['Authorization'] -eq 'bearer tok123'
            }
        }

        It 'Should use the installed_client grant when no secret is set' {
            Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot' | Out-Null
            Should -Invoke -ModuleName PSRedditTUI Invoke-RestMethod -Times 1 -ParameterFilter {
                $Body.grant_type -eq 'https://oauth.reddit.com/grants/installed_client' -and
                $Body.device_id -eq 'DO_NOT_TRACK_THIS_DEVICE'
            }
        }

        It 'Should cache the token across requests' {
            Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot' | Out-Null
            Get-RedditData -Url 'https://www.reddit.com/r/powershell/new' | Out-Null
            Should -Invoke -ModuleName PSRedditTUI Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*api/v1/access_token'
            }
        }

        It 'Should include the username in the User-Agent' {
            Get-RedditData -Url 'https://www.reddit.com/r/powershell/hot' | Out-Null
            Should -Invoke -ModuleName PSRedditTUI Invoke-WebRequest -Times 1 -ParameterFilter {
                $UserAgent -like '*(by /u/tester)'
            }
        }
    }

    Context 'Post mapping' {
        BeforeEach {
            Mock -ModuleName PSRedditTUI Invoke-WebRequest { New-FakeWebResponse -Content $script:listingJson }
        }

        It 'Get-RedditPosts should map posts and capture the pagination cursor' {
            $posts = @(Get-RedditPosts -Subreddit 'powershell')
            $posts.Count | Should -Be 2
            $posts[0].Title | Should -Be 'Tips & tricks <2026>'
            InModuleScope PSRedditTUI { $script:AfterCursor } | Should -Be 't3_next'
        }

        It 'Should treat self posts as non-links and link posts as links' {
            $posts = @(Get-RedditPosts -Subreddit 'powershell')
            $posts[0].IsLink | Should -BeFalse
            $posts[1].IsLink | Should -BeTrue
            $posts[1].LinkUrl | Should -Be 'https://example.com/article'
        }

        It 'Search-Reddit should go through Get-RedditData with an encoded query' {
            $posts = @(Search-Reddit -Query 'a&b c' -Subreddit 'powershell')
            $posts.Count | Should -Be 2
            Should -Invoke -ModuleName PSRedditTUI Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://www.reddit.com/r/powershell/search.json?q=a%26b%20c&restrict_sr=on&sort=relevance&t=all&raw_json=1'
            }
        }

        It 'Search-Reddit should reject an invalid subreddit name' {
            { Search-Reddit -Query 'x' -Subreddit '../evil' } | Should -Throw
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

Describe 'Install-PSRedditTUITerminalGui' {
    It 'Should exist as a function' {
        Get-Command -Name Install-PSRedditTUITerminalGui -Module PSRedditTUI | Should -Not -BeNullOrEmpty
    }

    It 'Should be exported by the module' {
        $module = Get-Module PSRedditTUI
        $module.ExportedFunctions.Keys | Should -Contain 'Install-PSRedditTUITerminalGui'
    }

    It 'Should have Version parameter' {
        $cmd = Get-Command -Name Install-PSRedditTUITerminalGui -Module PSRedditTUI
        $cmd.Parameters.Keys | Should -Contain 'Version'
    }

    It 'Should have Force parameter' {
        $cmd = Get-Command -Name Install-PSRedditTUITerminalGui -Module PSRedditTUI
        $cmd.Parameters.Keys | Should -Contain 'Force'
    }

    It 'Should have CmdletBinding attribute' {
        $cmd = Get-Command -Name Install-PSRedditTUITerminalGui -Module PSRedditTUI
        $cmd.CmdletBinding | Should -Be $true
    }
}
