BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Test-PocketTransientError' {
    It 'treats 5xx / 429 / 408 as transient and 4xx as not' {
        InModuleScope PocketPrep {
            (Test-PocketTransientError ([pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 503 }; Message = 'x' })) | Should -BeTrue
            (Test-PocketTransientError ([pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 429 }; Message = 'x' })) | Should -BeTrue
            (Test-PocketTransientError ([pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 404 }; Message = 'x' })) | Should -BeFalse
            (Test-PocketTransientError ([pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 403 }; Message = 'x' })) | Should -BeFalse
        }
    }
    It 'treats connection/timeout exceptions as transient' {
        InModuleScope PocketPrep {
            (Test-PocketTransientError ([System.Net.Http.HttpRequestException]::new('boom'))) | Should -BeTrue
            (Test-PocketTransientError ([System.Exception]::new('the request timed out'))) | Should -BeTrue
            (Test-PocketTransientError ([System.Exception]::new('totally unrelated'))) | Should -BeFalse
        }
    }
}

Describe 'Invoke-PocketWithRetry' {
    It 'retries a transient failure then succeeds' {
        InModuleScope PocketPrep {
            $script:n = 0
            $r = Invoke-PocketWithRetry -OperationName 'test' -BaseDelaySeconds 0 -Action {
                $script:n++
                if ($script:n -lt 3) { throw [System.Net.Http.HttpRequestException]::new('temporary') }
                'ok'
            }
            $r | Should -Be 'ok'
            $script:n | Should -Be 3
        }
    }
    It 'does NOT retry a non-transient failure' {
        InModuleScope PocketPrep {
            $script:n = 0
            { Invoke-PocketWithRetry -OperationName 'test' -BaseDelaySeconds 0 -Action {
                $script:n++; throw [pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 404 }; Message = 'nope' } } } | Should -Throw
            $script:n | Should -Be 1
        }
    }
    It 'gives up after MaxRetries' {
        InModuleScope PocketPrep {
            $script:n = 0
            { Invoke-PocketWithRetry -OperationName 'test' -MaxRetries 2 -BaseDelaySeconds 0 -Action {
                $script:n++; throw [System.Net.Http.HttpRequestException]::new('always') } } | Should -Throw
            $script:n | Should -Be 3   # initial + 2 retries
        }
    }
}

Describe 'Invoke-PocketDownload' {
    BeforeEach { $script:out = Join-Path ([System.IO.Path]::GetTempPath()) ("dl_" + [System.IO.Path]::GetRandomFileName()) }
    AfterEach { Remove-Item $script:out -Force -ErrorAction SilentlyContinue }

    It 'writes the file via an injected sender and returns its size' {
        $size = InModuleScope PocketPrep -Parameters @{ out = $script:out } {
            param($out)
            Invoke-PocketDownload -Uri 'https://example/x' -OutFile $out -RequestSender { param($u, $o, $t) 'abcd' | Set-Content -LiteralPath $o -NoNewline }
        }
        (Get-Content $script:out -Raw) | Should -Be 'abcd'
        $size | Should -Be 4
    }
    It 'refuses (and deletes) a file larger than MaxBytes' {
        InModuleScope PocketPrep -Parameters @{ out = $script:out } {
            param($out)
            { Invoke-PocketDownload -Uri 'https://example/x' -OutFile $out -MaxBytes 2 -RequestSender { param($u, $o, $t) 'toolong' | Set-Content -LiteralPath $o -NoNewline } } | Should -Throw
        }
        (Test-Path $script:out) | Should -BeFalse
    }
    It 'retries a transient sender failure' {
        $size = InModuleScope PocketPrep -Parameters @{ out = $script:out } {
            param($out)
            $script:dn = 0
            Invoke-PocketDownload -Uri 'https://example/x' -OutFile $out -RequestSender {
                param($u, $o, $t)
                $script:dn++
                if ($script:dn -lt 2) { throw [System.Net.Http.HttpRequestException]::new('flaky') }
                'ok' | Set-Content -LiteralPath $o -NoNewline
            }
        }
        $size | Should -Be 2
    }
}
