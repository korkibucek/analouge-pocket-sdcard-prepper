BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Get-PocketDirectoryListing' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path (Join-Path $script:root 'GameBoy') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:root 'NES') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:root '.hidden') -Force | Out-Null
        'x' | Set-Content (Join-Path $script:root 'afile.txt')
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'lists sub-folders (not files, not dot-folders) with a parent and roots' {
        $r = Get-PocketDirectoryListing -Path $script:root
        $names = @($r.Directories.Name)
        $names | Should -Contain 'GameBoy'
        $names | Should -Contain 'NES'
        $names | Should -Not -Contain '.hidden'
        $names | Should -Not -Contain 'afile.txt'
        $r.Parent | Should -Not -BeNullOrEmpty
        @($r.Roots).Count | Should -BeGreaterThan 0
    }

    It 'falls back to the home folder for a blank or missing path' {
        $blank = Get-PocketDirectoryListing -Path ''
        $blank.Path | Should -Not -BeNullOrEmpty
        $missing = Get-PocketDirectoryListing -Path (Join-Path $script:root 'does-not-exist')
        $missing.Path | Should -Be $blank.Path   # both fall back to home
    }

    It 'does not throw on a directory it cannot list' {
        { Get-PocketDirectoryListing -Path $script:root } | Should -Not -Throw
    }

    It 'returns no files without a pattern' {
        $r = Get-PocketDirectoryListing -Path $script:root
        @($r.Files).Count | Should -Be 0
    }

    It 'lists matching files (name/path/size) with -FilePattern, omitting non-matches and dot-files' {
        'z' | Set-Content (Join-Path $script:root 'core.zip')
        'z' | Set-Content (Join-Path $script:root 'other.zip')
        'h' | Set-Content (Join-Path $script:root '.hidden.zip')
        $r = Get-PocketDirectoryListing -Path $script:root -FilePattern '*.zip'
        $names = @($r.Files.Name)
        $names | Should -Contain 'core.zip'
        $names | Should -Contain 'other.zip'
        $names | Should -Not -Contain 'afile.txt'
        $names | Should -Not -Contain '.hidden.zip'
        @($r.Files | Where-Object Name -eq 'core.zip')[0].SizeBytes | Should -BeGreaterThan 0
        # Folders still listed alongside, so the picker can keep navigating.
        @($r.Directories.Name) | Should -Contain 'GameBoy'
    }
}

Describe 'POST /api/browse' {
    It 'returns a directory listing for the given path' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("dlapi_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path (Join-Path $dir 'Sub') -Force | Out-Null
        $body = [pscustomobject]@{ path = $dir }
        $r = InModuleScope PocketPrep -Parameters @{ b = $body } { param($b)
            Invoke-PocketApiRoute -Method POST -Path '/api/browse' -Body $b -State @{ Root = '/x' } }
        $r.Status | Should -Be 200
        @($r.Body.Directories.Name) | Should -Contain 'Sub'
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'lists matching files when the body carries a filePattern (#195)' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("dlapi_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        'z' | Set-Content (Join-Path $dir 'jtngpc.zip')
        'n' | Set-Content (Join-Path $dir 'notes.txt')
        $body = [pscustomobject]@{ path = $dir; filePattern = '*.zip' }
        $r = InModuleScope PocketPrep -Parameters @{ b = $body } { param($b)
            Invoke-PocketApiRoute -Method POST -Path '/api/browse' -Body $b -State @{ Root = '/x' } }
        $r.Status | Should -Be 200
        @($r.Body.Files.Name) | Should -Be @('jtngpc.zip')
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
