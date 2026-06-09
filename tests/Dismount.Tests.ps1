BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Dismount-PocketDrive' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("dm_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It '-FlushOnly flushes and does not attempt to eject (no throw)' {
        $r = Dismount-PocketDrive -Root $script:root -FlushOnly
        $r.Skipped | Should -BeTrue
        $r.Ejected | Should -BeFalse
        $r.Message | Should -Not -BeNullOrEmpty
    }

    It 'returns a result without throwing for a normal folder' {
        { Dismount-PocketDrive -Root $script:root -FlushOnly } | Should -Not -Throw
        (Dismount-PocketDrive -Root $script:root -FlushOnly).PSObject.TypeNames | Should -Contain 'PocketPrep.DismountResult'
    }
}
