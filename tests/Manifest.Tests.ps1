BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:systemsPath = Join-Path $repo 'manifests/systems.json'
}

Describe 'Get-PocketSystem' {
    It 'loads the shipped systems manifest' {
        $s = Get-PocketSystem -Path $script:systemsPath
        $s.Count | Should -BeGreaterThan 5
    }

    It 'computes the ROM destination as Assets/<platformId>/common' {
        $gb = Get-PocketSystem -Path $script:systemsPath -Id 'gb'
        $gb.RomDestinationRelative | Should -Match 'Assets[\\/]gb[\\/]common'
        $gb.SupportedExtensions | Should -Contain '.gb'
    }

    It 'lowercases extensions' {
        $snes = Get-PocketSystem -Path $script:systemsPath -Id 'snes'
        $snes.SupportedExtensions | Should -Contain '.sfc'
    }

    It 'throws for an unknown id' {
        { Get-PocketSystem -Path $script:systemsPath -Id 'nope' } | Should -Throw
    }

    It 'marks Neo Geo experimental and standard systems not' {
        (Get-PocketSystem -Path $script:systemsPath -Id 'neogeo').Experimental | Should -BeTrue
        (Get-PocketSystem -Path $script:systemsPath -Id 'gb').Experimental | Should -BeFalse
        (Get-PocketSystem -Path $script:systemsPath -Id 'nes').Experimental | Should -BeFalse
    }

    It 'rejects a manifest with duplicate ids' {
        $bad = Join-Path ([System.IO.Path]::GetTempPath()) ("sys_" + [System.IO.Path]::GetRandomFileName() + '.json')
        '{ "systems":[{"id":"gb","displayName":"a","platformId":"gb","supportedExtensions":[".gb"]},{"id":"gb","displayName":"b","platformId":"gb","supportedExtensions":[".gb"]}] }' | Set-Content $bad
        { Get-PocketSystem -Path $bad } | Should -Throw
        Remove-Item $bad -Force
    }

    It 'rejects an invalid extension format' {
        $bad = Join-Path ([System.IO.Path]::GetTempPath()) ("sys_" + [System.IO.Path]::GetRandomFileName() + '.json')
        '{ "systems":[{"id":"x","displayName":"a","platformId":"x","supportedExtensions":["gb"]}] }' | Set-Content $bad
        { Get-PocketSystem -Path $bad } | Should -Throw
        Remove-Item $bad -Force
    }
}
