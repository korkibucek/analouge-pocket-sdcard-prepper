BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:coresManifest = Join-Path $repo 'manifests/cores.json'

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Build a zip from a hashtable of @{ 'entry/name' = 'content' }. Allows arbitrary
    # entry names (including unsafe ones) so we can test zip-slip defences.
    function New-TestZip([hashtable]$Entries) {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("ppz_" + [System.IO.Path]::GetRandomFileName() + '.zip')
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
        $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries.Keys) {
                $entry = $archive.CreateEntry($name)
                $writer = [System.IO.StreamWriter]::new($entry.Open())
                $writer.Write([string]$Entries[$name])
                $writer.Dispose()
            }
        } finally {
            $archive.Dispose(); $fs.Dispose()
        }
        return $path
    }
}

Describe 'Get-PocketCoreManifest / Resolve-PocketCore' {
    It 'loads the shipped cores manifest' {
        (Get-PocketCoreManifest -Path $script:coresManifest).cores.Count | Should -BeGreaterThan 3
    }
    It 'resolves a core by id with GitHub coordinates' {
        $m = Get-PocketCoreManifest -Path $script:coresManifest
        $c = Resolve-PocketCore -Manifest $m -Id 'nes'
        $c.Identifier | Should -Be 'agg23.NES'
        $c.Owner | Should -Be 'agg23'
        $c.PlatformIds | Should -Contain 'nes'
    }
    It 'throws for an unknown core id' {
        $m = Get-PocketCoreManifest -Path $script:coresManifest
        { Resolve-PocketCore -Manifest $m -Id 'nope' } | Should -Throw
    }
}

Describe 'Test-PocketCoreZip' {
    It 'accepts a well-formed openFPGA core zip' {
        $zip = New-TestZip @{
            'Cores/Test.Core/core.json'      = '{}'
            'Platforms/gb.json'              = '{}'
            'Assets/gb/common/placeholder'   = 'x'
        }
        $v = Test-PocketCoreZip -Path $zip -ExpectedIdentifier 'Test.Core'
        $v.Valid | Should -BeTrue
        $v.HasStructure | Should -BeTrue
        $v.HasExpectedCore | Should -BeTrue
        Remove-Item $zip -Force
    }
    It 'rejects a zip without openFPGA structure' {
        $zip = New-TestZip @{ 'random/file.txt' = 'x' }
        (Test-PocketCoreZip -Path $zip).HasStructure | Should -BeFalse
        Remove-Item $zip -Force
    }
    It 'flags unsafe (zip-slip) entries' {
        $zip = New-TestZip @{ 'Cores/Test.Core/ok' = 'x'; '../evil.txt' = 'pwned' }
        $v = Test-PocketCoreZip -Path $zip
        $v.UnsafeEntries.Count | Should -BeGreaterThan 0
        $v.Valid | Should -BeFalse
        Remove-Item $zip -Force
    }
    It 'reports a missing expected core' {
        $zip = New-TestZip @{ 'Cores/Other.Core/x' = 'x'; 'Platforms/p.json' = '{}' }
        (Test-PocketCoreZip -Path $zip -ExpectedIdentifier 'Test.Core').HasExpectedCore | Should -BeFalse
        Remove-Item $zip -Force
    }
}

Describe 'Install-PocketCore (offline)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_core_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:core = [pscustomobject]@{ Id='test'; Identifier='Test.Core'; Owner='x'; Repo='y'; PlatformIds=@('gb') }
        $script:zip = New-TestZip @{
            'Cores/Test.Core/core.json'    = '{"v":1}'
            'Platforms/gb.json'            = '{}'
            'Assets/gb/common/placeholder' = 'x'
            'unrelated/junk.txt'           = 'ignored'
        }
    }
    AfterEach {
        Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $script:zip -Force -ErrorAction SilentlyContinue
    }

    It 'extracts only openFPGA folders onto the root' {
        $r = Install-PocketCore -Root $script:root -LocalZip $script:zip -Core $script:core
        $r.PlacedCount | Should -BeGreaterThan 0
        (Test-Path (Join-Path $script:root 'Cores/Test.Core/core.json')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Platforms/gb.json')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'unrelated/junk.txt')) | Should -BeFalse
    }

    It 'is non-destructive (skips existing files) unless -Overwrite' {
        Install-PocketCore -Root $script:root -LocalZip $script:zip -Core $script:core | Out-Null
        $r2 = Install-PocketCore -Root $script:root -LocalZip $script:zip -Core $script:core
        $r2.SkippedCount | Should -BeGreaterThan 0
        $r2.PlacedCount | Should -Be 0
        $r3 = Install-PocketCore -Root $script:root -LocalZip $script:zip -Core $script:core -Overwrite
        $r3.PlacedCount | Should -BeGreaterThan 0
    }

    It 'DryRun writes nothing' {
        $r = Install-PocketCore -Root $script:root -LocalZip $script:zip -Core $script:core -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Cores')) | Should -BeFalse
    }

    It 'refuses a zip-slip zip' {
        $evil = New-TestZip @{ 'Cores/Test.Core/ok' = 'x'; '../evil.txt' = 'pwned' }
        { Install-PocketCore -Root $script:root -LocalZip $evil -Core $script:core } | Should -Throw
        Remove-Item $evil -Force
    }

    It 'refuses a zip missing the expected core' {
        $wrong = New-TestZip @{ 'Cores/Other.Core/x' = 'x'; 'Platforms/p.json' = '{}' }
        { Install-PocketCore -Root $script:root -LocalZip $wrong -Core $script:core } | Should -Throw
        Remove-Item $wrong -Force
    }
}
