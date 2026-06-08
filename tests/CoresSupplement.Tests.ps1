BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:cm  = Join-Path $repo 'manifests/cores.json'
    $script:sup = Join-Path $repo 'manifests/cores-supplement.json'
}

Describe 'Curated cores supplement' {
    It 'every supplement core is present in the generated cores.json' {
        $supp = (Get-Content $script:sup -Raw | ConvertFrom-Json).cores
        $cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $script:cm)
        $haveRepos = @($cores | ForEach-Object { "$($_.Owner)/$($_.Repo)".ToLowerInvariant() })
        foreach ($s in $supp) {
            $haveRepos | Should -Contain "$($s.owner)/$($s.repo)".ToLowerInvariant()
        }
    }

    It 'includes the verified new community cores' {
        $cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $script:cm)
        $ids = @($cores.Id)
        foreach ($id in 'agg23-gameandwatch', 'agg23-tamagotchi', 'budude2-gbc', 'mazamars312-pcecd', 'rndmnkiii-analogizer-genesis', 'thinkelastic-doom', 'thinkelastic-quake') {
            $ids | Should -Contain $id
        }
    }

    It 'supplement cores all have an owner/repo (so they can be downloaded)' {
        $supp = (Get-Content $script:sup -Raw | ConvertFrom-Json).cores
        foreach ($s in $supp) {
            $s.owner | Should -Not -BeNullOrEmpty
            $s.repo  | Should -Not -BeNullOrEmpty
        }
    }
}
