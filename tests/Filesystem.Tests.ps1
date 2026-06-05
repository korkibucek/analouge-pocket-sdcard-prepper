BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Test-PocketFilesystem' {
    It 'accepts exFAT' {
        $v = Test-PocketFilesystem -FileSystem 'exFAT'
        $v.Acceptable | Should -BeTrue
        $v.Remediation | Should -BeNullOrEmpty
    }

    It 'accepts FAT32 but warns about the 4 GB limit' {
        $v = Test-PocketFilesystem -FileSystem 'FAT32'
        $v.Acceptable | Should -BeTrue
        $v.Remediation | Should -Match '4 GB'
    }

    It 'rejects NTFS with remediation' {
        $v = Test-PocketFilesystem -FileSystem 'NTFS'
        $v.Acceptable | Should -BeFalse
        $v.Remediation | Should -Match 'exFAT'
    }

    It 'rejects an unknown/empty filesystem' {
        $v = Test-PocketFilesystem -FileSystem ''
        $v.Acceptable | Should -BeFalse
    }

    It 'is case-insensitive' {
        (Test-PocketFilesystem -FileSystem 'exfat').Acceptable | Should -BeTrue
        (Test-PocketFilesystem -FileSystem 'FAT32').Acceptable | Should -BeTrue
    }

    It 'accepts Linux lsblk spellings (vfat -> FAT32, exfat)' {
        $v = Test-PocketFilesystem -FileSystem 'vfat'
        $v.Acceptable | Should -BeTrue
        $v.CanonicalFileSystem | Should -Be 'FAT32'
        (Test-PocketFilesystem -FileSystem 'exfat').CanonicalFileSystem | Should -Be 'EXFAT'
    }

    It 'accepts macOS spellings (MS-DOS (FAT32), ExFAT)' {
        (Test-PocketFilesystem -FileSystem 'MS-DOS (FAT32)').Acceptable | Should -BeTrue
        (Test-PocketFilesystem -FileSystem 'ExFAT').Acceptable | Should -BeTrue
    }

    It 'rejects FAT16 with specific remediation' {
        $v = Test-PocketFilesystem -FileSystem 'FAT16'
        $v.Acceptable | Should -BeFalse
        $v.CanonicalFileSystem | Should -Be 'FAT16'
        $v.Remediation | Should -Match 'FAT16'
    }
}
