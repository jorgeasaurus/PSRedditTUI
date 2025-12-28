#Requires -Version 7.0
#Requires -Modules InvokeBuild

<#
.SYNOPSIS
    InvokeBuild script for PSRedditTUI
.DESCRIPTION
    Defines build tasks for testing, analyzing, building, and publishing the module.
#>

# Build configuration
$ModuleName = 'PSRedditTUI'
$SourcePath = $BuildRoot
$BuildPath = Join-Path -Path $BuildRoot -ChildPath 'build'
$ModuleBuildPath = Join-Path -Path $BuildPath -ChildPath $ModuleName

# Files to include in the build
$ModuleFiles = @(
    'PSRedditTUI.psd1'
    'PSRedditTUI.psm1'
)

# No subfolders in this module structure
$ModuleFolders = @()

# Synopsis: Remove build artifacts
task Clean {
    if (Test-Path -Path $BuildPath) {
        Write-Build Yellow "Removing build directory: $BuildPath"
        Remove-Item -Path $BuildPath -Recurse -Force
    }
}

# Synopsis: Run PSScriptAnalyzer
task Analyze {
    Write-Build White "Running PSScriptAnalyzer..."

    $analyzerParams = @{
        Path        = $SourcePath
        Recurse     = $true
        ExcludeRule = @(
            'PSAvoidUsingWriteHost'  # Used intentionally for colored console output in example/helper scripts
        )
        Severity    = @('Error', 'Warning')
    }

    # Exclude build output and dev/test artifacts from analysis
    $excludePaths = @(
        (Join-Path $SourcePath 'build')
    )

    $results = Get-ChildItem -Path $SourcePath -Include '*.ps1', '*.psm1', '*.psd1' -Recurse |
        Where-Object {
            # Exclude paths
            $excludePath = $false
            foreach ($ep in $excludePaths) {
                if ($_.FullName.StartsWith($ep)) { $excludePath = $true; break }
            }
            -not $excludePath
        } |
        ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName @analyzerParams }

    if ($results) {
        $results | Format-Table -AutoSize
        $errorCount = ($results | Where-Object { $_.Severity -eq 'Error' }).Count
        $warningCount = ($results | Where-Object { $_.Severity -eq 'Warning' }).Count

        Write-Build Yellow "PSScriptAnalyzer found $errorCount errors and $warningCount warnings"

        if ($errorCount -gt 0) {
            throw "PSScriptAnalyzer found $errorCount errors. Please fix them before building."
        }
    } else {
        Write-Build Green "PSScriptAnalyzer found no issues"
    }
}

# Synopsis: Run Pester tests
task Test {
    Write-Build White "Running Pester tests..."

    $testsPath = Join-Path -Path $SourcePath -ChildPath 'Tests'

    if (-not (Test-Path $testsPath)) {
        Write-Build Yellow "Tests directory not found, skipping tests"
        return
    }

    $testFiles = Get-ChildItem -Path $testsPath -Filter '*.Tests.ps1' -Recurse
    if ($testFiles.Count -eq 0) {
        Write-Build Yellow "No test files found, skipping tests"
        return
    }

    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $testsPath
    $pesterConfig.Run.Exit = $false
    $pesterConfig.Output.Verbosity = 'Detailed'

    # Import the module for testing (skip TUI functions if Terminal.Gui unavailable)
    $modulePath = Join-Path -Path $SourcePath -ChildPath 'PSRedditTUI.psd1'
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force -ErrorAction Stop
        }
        catch {
            Write-Build Yellow "Module import failed (Terminal.Gui may not be available): $_"
            Write-Build Yellow "Running tests without module import"
        }
    }

    $testResult = Invoke-Pester -Configuration $pesterConfig

    if ($testResult.FailedCount -gt 0) {
        throw "Pester tests failed: $($testResult.FailedCount) of $($testResult.TotalCount) tests failed"
    }

    Write-Build Green "All $($testResult.PassedCount) tests passed"
}

# Synopsis: Build the module for distribution
task Build Clean, {
    Write-Build White "Building module to: $ModuleBuildPath"

    # Create build directory
    New-Item -Path $ModuleBuildPath -ItemType Directory -Force | Out-Null

    # Copy module files
    foreach ($file in $ModuleFiles) {
        $sourceFilePath = Join-Path -Path $SourcePath -ChildPath $file
        if (Test-Path $sourceFilePath) {
            Copy-Item -Path $sourceFilePath -Destination $ModuleBuildPath -Force
            Write-Build Gray "  Copied: $file"
        } else {
            Write-Build Yellow "  Warning: $file not found"
        }
    }

    # Copy module folders
    foreach ($folder in $ModuleFolders) {
        $sourceFolderPath = Join-Path -Path $SourcePath -ChildPath $folder
        if (Test-Path $sourceFolderPath) {
            $destFolderPath = Join-Path -Path $ModuleBuildPath -ChildPath $folder
            Copy-Item -Path $sourceFolderPath -Destination $destFolderPath -Recurse -Force
            Write-Build Gray "  Copied: $folder/"
        } else {
            Write-Build Yellow "  Warning: $folder/ not found"
        }
    }

    # Validate the built module
    Write-Build White "Validating built module..."
    $builtManifest = Join-Path -Path $ModuleBuildPath -ChildPath 'PSRedditTUI.psd1'
    $manifestData = Test-ModuleManifest -Path $builtManifest -ErrorAction Stop
    Write-Build Green "Module validated: $($manifestData.Name) v$($manifestData.Version)"
}

# Synopsis: Publish module to PSGallery
task Publish Build, {
    Write-Build White "Publishing to PSGallery..."

    $apiKey = $env:PSGALLERY_API_KEY
    if (-not $apiKey) {
        throw "PSGALLERY_API_KEY environment variable not set"
    }

    $publishParams = @{
        Path        = $ModuleBuildPath
        NuGetApiKey = $apiKey
        ErrorAction = 'Stop'
    }

    Publish-Module @publishParams
    Write-Build Green "Module published to PSGallery"
}

# Synopsis: Get module version from manifest
task GetVersion {
    $manifestPath = Join-Path -Path $SourcePath -ChildPath 'PSRedditTUI.psd1'
    $manifestData = Import-PowerShellDataFile -Path $manifestPath
    $version = $manifestData.ModuleVersion

    Write-Build Green "Module version: $version"

    # Output for GitHub Actions
    if ($env:GITHUB_OUTPUT) {
        "version=$version" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    }

    return $version
}

# Synopsis: Get release notes from manifest
task GetReleaseNotes {
    $manifestPath = Join-Path -Path $SourcePath -ChildPath 'PSRedditTUI.psd1'
    $manifestData = Import-PowerShellDataFile -Path $manifestPath
    $releaseNotes = $manifestData.PrivateData.PSData.ReleaseNotes

    Write-Build White "Release Notes:"
    Write-Build Gray $releaseNotes

    # Output for GitHub Actions (escape newlines)
    if ($env:GITHUB_OUTPUT) {
        $escapedNotes = $releaseNotes -replace "`n", '%0A' -replace "`r", ''
        "release_notes=$escapedNotes" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    }

    return $releaseNotes
}

# Synopsis: Default task - run tests and build
task . Analyze, Test, Build

# Synopsis: CI task - full validation without publishing
task CI Analyze, Test, Build

# Synopsis: Release task - build and publish
task Release Analyze, Test, Publish
