BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:repo = $repo
}

Describe 'Invoke-PocketApiRoute' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_api_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:state = @{
            Root = $script:root; IsTestMode = $true; DryRun = $false
            FirmwareManifest = (Join-Path $script:repo 'manifests/firmware.json')
            SystemsManifest  = (Join-Path $script:repo 'manifests/systems.json')
            CoresManifest    = (Join-Path $script:repo 'manifests/cores.json')
        }
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'GET /api/health returns ok' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/health' -State $s }
        $r.Status | Should -Be 200
        $r.Body.ok | Should -BeTrue
    }
    It 'GET /api/drives uses an injected provider' {
        $state = $script:state.Clone()
        $state.DriveProvider = { @([pscustomobject]@{ DriveLetter='/mnt/x'; RootPath='/mnt/x'; Label='X'; FileSystem='exFAT'; SizeBytes=64GB; FreeBytes=64GB; IsRemovable=$true; BusType='USB'; MediaType='' }) }
        $r = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/drives' -State $s }
        @($r.Body.drives).Count | Should -Be 1
    }
    It 'GET /api/drives surfaces fixed likely-card candidates separately' {
        $state = $script:state.Clone()
        $state.DriveProvider = {
            @(
                [pscustomobject]@{ DriveLetter='C:'; RootPath='C:\'; Label='OS'; FileSystem='NTFS'; SizeBytes=1TB; FreeBytes=1GB; IsRemovable=$false; BusType='NVMe'; MediaType='' },
                [pscustomobject]@{ DriveLetter='G:'; RootPath='G:\'; Label='CARD'; FileSystem='exFAT'; SizeBytes=64GB; FreeBytes=64GB; IsRemovable=$false; BusType='SATA'; MediaType='' }
            )
        }
        $r = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/drives' -State $s }
        @($r.Body.drives).Count | Should -Be 0           # neither is removable, IncludeFixed off
        @($r.Body.candidates).Count | Should -Be 1       # the exFAT 64GB fixed disk
        $r.Body.candidates[0].RootPath | Should -Be 'G:\'
    }
    It 'GET /api/empty reports a fresh root empty' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/empty' -State $s }
        $r.Body.IsEmpty | Should -BeTrue
    }
    It 'POST /api/folders creates the structure' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/folders' -State $s }
        $r.Body.Created | Should -Contain 'Assets'
    }
    It 'GET /api/systems returns systems' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/systems' -State $s }
        @($r.Body.systems).Count | Should -BeGreaterThan 5
    }
    It 'POST /api/rom/plan matches ROMs' {
        $src = Join-Path $script:root '_src'; New-Item -ItemType Directory $src -Force | Out-Null
        'x' | Set-Content (Join-Path $src 'g.gb')
        $body = [pscustomobject]@{ systemId='gb'; sourceFolder=$src }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/plan' -Body $b -State $s }
        $r.Body.FileCount | Should -Be 1
    }
    It 'POST /api/target sets a test-mode root' {
        $newRoot = Join-Path $script:root 'chosen'
        $body = [pscustomobject]@{ testMode = $true; rootPath = $newRoot }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/target' -Body $b -State $s }
        $r.Status | Should -Be 200
        $r.Body.ready | Should -BeTrue
        $script:state.Root | Should -Be (Resolve-Path $newRoot).Path
    }
    It 'POST /api/target rejects an unsafe (system) drive' {
        $body = [pscustomobject]@{ drive = [pscustomobject]@{ DriveLetter='/'; RootPath='/'; IsRemovable=$false; SizeBytes=1TB } }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/target' -Body $b -State $s }
        $r.Status | Should -Be 400
        $r.Body.verdict | Should -Not -BeNullOrEmpty
    }
    It 'POST /api/rom/plan includes PlatformProvided' {
        $src = Join-Path $script:root '_src2'; New-Item -ItemType Directory $src -Force | Out-Null
        'x' | Set-Content (Join-Path $src 'g.gb')
        $body = [pscustomobject]@{ systemId='gb'; sourceFolder=$src }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/plan' -Body $b -State $s }
        $r.Body.PSObject.Properties.Name | Should -Contain 'PlatformProvided'
        $r.Body.PlatformProvided | Should -BeFalse   # no cores installed in this temp root
    }
    It 'GET /api/cores/updates returns an updates array' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/cores/updates' -State $s }
        $r.Status | Should -Be 200
        $r.Body.ContainsKey('updates') | Should -BeTrue
    }
    It 'unknown route returns 404' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/nope' -State $s }
        $r.Status | Should -Be 404
    }
    It 'route errors are returned as 400, not thrown' {
        $body = [pscustomobject]@{ systemId='gb'; sourceFolder='/does/not/exist' }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/plan' -Body $b -State $s }
        $r.Status | Should -Be 400
        $r.Body.error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-PocketApiRequest (auth)' {
    It 'allows a request with the right token and loopback host' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'X-PocketPrep-Token'='abc'; 'Host'='127.0.0.1:9999' } -ExpectedToken 'abc' -Port 9999 }
        $r.Allowed | Should -BeTrue
    }
    It 'rejects a missing/incorrect token (401)' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'Host'='127.0.0.1:9999' } -ExpectedToken 'abc' -Port 9999 }
        $r.Allowed | Should -BeFalse
        $r.Status | Should -Be 401
    }
    It 'rejects a foreign Host header (403)' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'X-PocketPrep-Token'='abc'; 'Host'='evil.example.com' } -ExpectedToken 'abc' -Port 9999 }
        $r.Status | Should -Be 403
    }
    It 'rejects a cross-origin request (403)' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'X-PocketPrep-Token'='abc'; 'Host'='127.0.0.1:9999'; 'Origin'='http://evil.example.com' } -ExpectedToken 'abc' -Port 9999 }
        $r.Status | Should -Be 403
    }
}
