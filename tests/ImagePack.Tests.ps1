BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    # Build a small image-pack zip with images under Platforms/_images and a junk file
    # outside it (must NOT be extracted).
    function New-ImagePackZip {
        param($Path, [switch]$WithTraversal)
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("ipstage_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path (Join-Path $stage 'Platforms/_images') -Force | Out-Null
        'img' | Set-Content (Join-Path $stage 'Platforms/_images/gb.bin')
        'img' | Set-Content (Join-Path $stage 'Platforms/_images/nes.bin')
        'junk' | Set-Content (Join-Path $stage 'readme.txt')   # outside _images -> ignored
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path $Path) { Remove-Item $Path -Force }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $Path)
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Install-PocketImagePack (offline zip)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("ip_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:zip = Join-Path ([System.IO.Path]::GetTempPath()) ("ipzip_" + [System.IO.Path]::GetRandomFileName() + '.zip')
        New-ImagePackZip -Path $script:zip
    }
    AfterEach { Remove-Item $script:root, $script:zip -Recurse -Force -ErrorAction SilentlyContinue }

    It 'extracts only Platforms/_images and nothing else' {
        $r = Install-PocketImagePack -Root $script:root -LocalZip $script:zip
        $r.PlacedCount | Should -Be 2
        (Test-Path (Join-Path $script:root 'Platforms/_images/gb.bin')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Platforms/_images/nes.bin')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'readme.txt')) | Should -BeFalse   # outside _images, ignored
    }

    It 'skips existing images unless -Overwrite' {
        Install-PocketImagePack -Root $script:root -LocalZip $script:zip | Out-Null
        $r2 = Install-PocketImagePack -Root $script:root -LocalZip $script:zip
        $r2.SkippedCount | Should -Be 2
        $r2.PlacedCount | Should -Be 0
        $r3 = Install-PocketImagePack -Root $script:root -LocalZip $script:zip -Overwrite
        $r3.PlacedCount | Should -Be 2
    }

    It 'DryRun extracts nothing' {
        $r = Install-PocketImagePack -Root $script:root -LocalZip $script:zip -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Platforms/_images/gb.bin')) | Should -BeFalse
    }

    It 'throws on a zip with no _images entries' {
        $bad = Join-Path ([System.IO.Path]::GetTempPath()) ("ipbad_" + [System.IO.Path]::GetRandomFileName() + '.zip')
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("ipbs_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        'x' | Set-Content (Join-Path $stage 'notes.txt')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $bad)
        try { { Install-PocketImagePack -Root $script:root -LocalZip $bad } | Should -Throw }
        finally { Remove-Item $bad, $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
