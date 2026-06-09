BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Get-PocketDiskSpace' {
    It 'returns free/total/used for an existing path' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("ds_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $s = Get-PocketDiskSpace -Path $dir
            $s.TotalBytes | Should -BeGreaterThan 0
            $s.FreeBytes  | Should -BeGreaterThan 0
            $s.UsedBytes  | Should -Be ($s.TotalBytes - $s.FreeBytes)
        } finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'degrades gracefully (nulls, no throw) for a non-existent path' {
        $s = Get-PocketDiskSpace -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist-xyz')
        $s.FreeBytes | Should -BeNullOrEmpty
    }
}
