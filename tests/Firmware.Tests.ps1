BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:manifestPath = Join-Path $repo 'manifests/firmware.json'
}

Describe 'Firmware manifest' {
    It 'loads and validates the shipped manifest' {
        $m = Get-PocketFirmwareManifest -Path $script:manifestPath
        $m.latest | Should -Not -BeNullOrEmpty
        $m.releases.Count | Should -BeGreaterThan 0
    }

    It 'resolves the latest release by default' {
        $m = Get-PocketFirmwareManifest -Path $script:manifestPath
        $r = Resolve-PocketFirmwareRelease -Manifest $m
        $r.version | Should -Be $m.latest
        $r.fileName | Should -Match '\.bin$'
        $r.md5 | Should -Match '^[0-9a-fA-F]{32}$'
    }

    It 'throws for an unknown version' {
        $m = Get-PocketFirmwareManifest -Path $script:manifestPath
        { Resolve-PocketFirmwareRelease -Manifest $m -Version '99.9' } | Should -Throw
    }

    It 'rejects a manifest with a bad md5' {
        $bad = Join-Path ([System.IO.Path]::GetTempPath()) ("bad_" + [System.IO.Path]::GetRandomFileName() + '.json')
        '{ "latest":"1.0","releases":[{"version":"1.0","releaseDate":"2020-01-01","url":"https://www.analogue.co/x","fileName":"f.bin","md5":"nothex","sizeBytes":1}] }' | Set-Content $bad
        { Get-PocketFirmwareManifest -Path $bad } | Should -Throw
        Remove-Item $bad -Force
    }
}

Describe 'Test-PocketFirmwareFile' {
    BeforeEach {
        $script:f = Join-Path ([System.IO.Path]::GetTempPath()) ("fw_" + [System.IO.Path]::GetRandomFileName() + '.bin')
        Set-Content -LiteralPath $script:f -Value 'firmware-bytes' -NoNewline
        $script:realMd5 = (Get-FileHash -LiteralPath $script:f -Algorithm MD5).Hash.ToLowerInvariant()
        $script:realSize = (Get-Item $script:f).Length
    }
    AfterEach { Remove-Item -LiteralPath $script:f -Force -ErrorAction SilentlyContinue }

    It 'validates a correct md5 and size' {
        $v = Test-PocketFirmwareFile -Path $script:f -ExpectedMd5 $script:realMd5 -ExpectedSizeBytes $script:realSize
        $v.Valid | Should -BeTrue
    }

    It 'fails on md5 mismatch' {
        $v = Test-PocketFirmwareFile -Path $script:f -ExpectedMd5 ('0' * 32)
        $v.Valid | Should -BeFalse
        ($v.Reasons -join ' ') | Should -Match 'MD5 mismatch'
    }

    It 'fails on size mismatch' {
        $v = Test-PocketFirmwareFile -Path $script:f -ExpectedMd5 $script:realMd5 -ExpectedSizeBytes 999999
        $v.Valid | Should -BeFalse
    }
}

Describe 'Install-PocketFirmware (offline placement)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_fw_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:local = Join-Path ([System.IO.Path]::GetTempPath()) ("src_" + [System.IO.Path]::GetRandomFileName() + '.bin')
        Set-Content -LiteralPath $script:local -Value 'pocket_firmware_payload' -NoNewline
        $script:md5 = (Get-FileHash -LiteralPath $script:local -Algorithm MD5).Hash.ToLowerInvariant()
    }
    AfterEach {
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:local -Force -ErrorAction SilentlyContinue
    }

    It 'places a verified local firmware file at the root' {
        $r = Install-PocketFirmware -Root $script:root -LocalFile $script:local -ExpectedMd5 $script:md5
        $r.Md5Verified | Should -BeTrue
        (Test-Path $r.Destination) | Should -BeTrue
    }

    It 'refuses to install on md5 mismatch' {
        { Install-PocketFirmware -Root $script:root -LocalFile $script:local -ExpectedMd5 ('0'*32) } | Should -Throw
        (Get-ChildItem $script:root -Filter *.bin).Count | Should -Be 0
    }

    It 'DryRun does not copy' {
        $r = Install-PocketFirmware -Root $script:root -LocalFile $script:local -ExpectedMd5 $script:md5 -DryRun
        $r.DryRun | Should -BeTrue
        (Get-ChildItem $script:root -Filter *.bin).Count | Should -Be 0
    }

    It 'warns about a different existing firmware .bin' {
        Set-Content -LiteralPath (Join-Path $script:root 'old_firmware_1_0.bin') -Value 'x'
        $r = Install-PocketFirmware -Root $script:root -LocalFile $script:local -ExpectedMd5 $script:md5
        ($r.Warnings -join ' ') | Should -Match 'only one firmware'
    }
}
