BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:cm = Join-Path $repo 'manifests/cores.json'
}

Describe 'Get-PocketLatestRelease -AssetPattern' {
    It 'picks the matching zip when a release ships several (default stays first-zip)' {
        $rel = InModuleScope PocketPrep {
            Mock Invoke-PocketRest { [pscustomobject]@{
                tag_name = '0.1.1'
                assets = @(
                    [pscustomobject]@{ name = 'boogermann.gberet_pocket-0.1.1.zip';      browser_download_url = 'https://github.com/x/pocket.zip' }
                    [pscustomobject]@{ name = 'boogermann.gberet_rom-recipes-0.1.1.zip'; browser_download_url = 'https://github.com/x/recipes.zip' }
                ) } }
            [pscustomobject]@{
                Default = Get-PocketLatestRelease -Owner 'o' -Repo 'r'
                Recipes = Get-PocketLatestRelease -Owner 'o' -Repo 'r' -AssetPattern 'rom[-_]?recipes'
            }
        }
        $rel.Default.ZipName | Should -Be 'boogermann.gberet_pocket-0.1.1.zip'
        $rel.Recipes.ZipName | Should -Be 'boogermann.gberet_rom-recipes-0.1.1.zip'
    }
}

Describe 'Save-PocketRomRecipe' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("rcp_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        # A real recipes zip the mocked download will "fetch".
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("rcps_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        'mra' | Set-Content (Join-Path $stage 'gberet.mra')
        $script:zip = Join-Path ([System.IO.Path]::GetTempPath()) ("rcpz_" + [System.IO.Path]::GetRandomFileName() + '.zip')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $script:zip)
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        $script:coreId = (Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $script:cm) | Select-Object -First 1).Id
    }
    AfterEach { Remove-Item $script:root, $script:zip -Recurse -Force -ErrorAction SilentlyContinue }

    It 'downloads and extracts the recipes to pocketprep/rom-recipes/<coreId>/' {
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; id = $script:coreId; zip = $script:zip } {
            param($root, $cm, $id, $zip)
            Mock Get-PocketLatestRelease { [pscustomobject]@{ Version='0.1.1'; ZipUrl='https://github.com/x/recipes.zip'; ZipName='recipes.zip' } }
            Mock Invoke-PocketDownload { Copy-Item -LiteralPath $zip -Destination $OutFile; $OutFile }
            Save-PocketRomRecipe -Root $root -CoreId $id -CoresManifest $cm
        }
        $r.PlacedCount | Should -Be 1
        (Test-Path (Join-Path $script:root "pocketprep/rom-recipes/$($script:coreId)/gberet.mra")) | Should -BeTrue
    }

    It 'throws clearly when the release has no rom-recipes asset' {
        { InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; id = $script:coreId } {
            param($root, $cm, $id)
            Mock Get-PocketLatestRelease { [pscustomobject]@{ Version='1.0'; ZipUrl=$null; ZipName=$null } }
            Save-PocketRomRecipe -Root $root -CoreId $id -CoresManifest $cm
        } } | Should -Throw '*No rom-recipes asset*'
    }

    It 'DryRun downloads nothing' {
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; id = $script:coreId } {
            param($root, $cm, $id)
            Mock Get-PocketLatestRelease { [pscustomobject]@{ Version='1.0'; ZipUrl='https://github.com/x/r.zip'; ZipName='r.zip' } }
            Mock Invoke-PocketDownload { throw 'must not download in dry-run' }
            Save-PocketRomRecipe -Root $root -CoreId $id -CoresManifest $cm -DryRun
        }
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'pocketprep/rom-recipes')) | Should -BeFalse
    }
}

Describe 'Test-PocketArcadeRomset' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("arc_" + [System.IO.Path]::GetRandomFileName())
        $script:common = Join-Path $script:root 'Assets/gberet/common'
        New-Item -ItemType Directory -Path $script:common -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'reports not ready when empty or only one half is present' {
        (Test-PocketArcadeRomset -Root $script:root -PlatformId 'gberet').Ready | Should -BeFalse
        'inst' | Set-Content (Join-Path $script:common 'Green Beret.json')
        $r = Test-PocketArcadeRomset -Root $script:root -PlatformId 'gberet'
        $r.InstanceJson | Should -Be 1
        $r.Ready | Should -BeFalse   # .rom still missing
    }

    It 'reports ready when an instance .json and a built .rom are present' {
        'inst' | Set-Content (Join-Path $script:common 'Green Beret.json')
        'rom'  | Set-Content (Join-Path $script:common 'gberet.rom')
        (Test-PocketArcadeRomset -Root $script:root -PlatformId 'gberet').Ready | Should -BeTrue
    }
}
