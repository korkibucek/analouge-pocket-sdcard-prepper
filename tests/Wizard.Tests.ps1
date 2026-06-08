BeforeAll {
    $script:repo = Split-Path -Parent $PSScriptRoot
    $script:wizard = Join-Path $script:repo 'src/Start-PocketPrep.ps1'
    $script:gbExamples = Join-Path $script:repo 'examples/fake-sd-source/GameBoy'

    # Runs the real wizard script as a subprocess with scripted answers on stdin,
    # against a fake SD root. Returns the captured stdout+stderr.
    function Invoke-Wizard {
        param([string[]] $Answers, [string[]] $WizardArgs)
        $inFile  = New-TemporaryFile
        $outFile = New-TemporaryFile
        $errFile = New-TemporaryFile
        (($Answers -join "`n") + "`n") | Set-Content -LiteralPath $inFile -NoNewline
        $args = @('-NoProfile', '-File', $script:wizard) + $WizardArgs
        $p = Start-Process -FilePath 'pwsh' -ArgumentList $args -NoNewWindow -Wait -PassThru `
            -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $out = (Get-Content -LiteralPath $outFile -Raw) + "`n" + (Get-Content -LiteralPath $errFile -Raw)
        Remove-Item $inFile, $outFile, $errFile -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Output = $out; ExitCode = $p.ExitCode }
    }
}

Describe 'Start-PocketPrep wizard (subprocess, fake SD root)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("wiz_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'completes the happy path (dry-run) skipping firmware, cores and all systems' {
        # firmware:n, install-cores:n, then 10 systems:n
        $answers = @('n', 'n') + (1..10 | ForEach-Object { 'n' })
        $r = Invoke-Wizard -Answers $answers -WizardArgs @('-TestMode', '-Root', $script:root, '-DryRun')
        $r.Output | Should -Match 'Summary'
        $r.Output | Should -Match 'Folders created: 9'
        $r.Output | Should -Match 'ROMs: none imported'
    }

    It 'imports Game Boy ROMs end-to-end and reports them in the summary' {
        # firmware:n, cores:n, gb:y, source, recurse:n, copy:y, then 9 systems:n, save-log:n
        $answers = @('n', 'n', 'y', $script:gbExamples, 'n', 'y') + (1..9 | ForEach-Object { 'n' }) + @('n')
        $r = Invoke-Wizard -Answers $answers -WizardArgs @('-TestMode', '-Root', $script:root)
        $r.Output | Should -Match 'gb: 2 copied'
        (Test-Path (Join-Path $script:root 'Assets/gb/common/demo-game.gb')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Assets/gb/common/another-demo.gb')) | Should -BeTrue
    }

    It 'saves the source mapping and a later run rescans it without re-entering folders' {
        $src = Join-Path ([System.IO.Path]::GetTempPath()) ("wizsrc_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        'a' | Set-Content (Join-Path $src 'one.gb')
        try {
            # Run 1: import GB from $src and save the folder list to the card.
            # firmware:n, cores:n, gb:y, source, recurse:n, copy:y, 9 systems:n, save-log:n
            $a1 = @('n', 'n', 'y', $src, 'n', 'y') + (1..9 | ForEach-Object { 'n' }) + @('n')
            Invoke-Wizard -Answers $a1 -WizardArgs @('-TestMode', '-Root', $script:root) | Out-Null
            (Test-Path (Join-Path $script:root 'pocketprep/rom-sources.json')) | Should -BeTrue

            # Add a new ROM, then Run 2: accept the rescan offer (no folder re-entry).
            # The card is now non-empty, so the run opens with backup/continue prompts.
            'b' | Set-Content (Join-Path $src 'two.gb')
            # backup-saves:n, continue:y, firmware:n, cores:n, rescan-saved:y, save-log:n
            $r2 = Invoke-Wizard -Answers @('n', 'y', 'n', 'n', 'y', 'n') -WizardArgs @('-TestMode', '-Root', $script:root)
            $r2.Output | Should -Match 'Rescan complete'
            (Test-Path (Join-Path $script:root 'Assets/gb/common/two.gb')) | Should -BeTrue
        } finally {
            Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It '-CleanFirst shows a dry-run preview then wipes after the typed-token confirmation' {
        # Non-test-mode run against an injected "removable" drive whose RootPath is our temp
        # folder, so the CleanFirst branch (gated off test mode) actually runs.
        'old game' | Set-Content (Join-Path $script:root 'oldgame.gb')
        New-Item -ItemType Directory -Path (Join-Path $script:root 'Assets') -Force | Out-Null
        $drivesJson = Join-Path ([System.IO.Path]::GetTempPath()) ("drv_" + [System.IO.Path]::GetRandomFileName() + '.json')
        @(@{ DriveLetter='X'; RootPath=$script:root; Label='POCKET'; FileSystem='exFAT'; SizeBytes=64424509440; FreeBytes=64000000000; IsRemovable=$true; BusType='usb'; MediaType='' }) |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $drivesJson
        # answers: select drive 0, wipe? y, token=POCKET, continue y, firmware n, cores n, 10 systems n, save-log n
        $answers = @('0', 'y', 'POCKET', 'y', 'n', 'n') + (1..10 | ForEach-Object { 'n' }) + @('n')
        $r = Invoke-Wizard -Answers $answers -WizardArgs @('-Root', $script:root, '-CleanFirst', '-DriveDataPath', $drivesJson)
        $r.Output | Should -Match 'Dry-run preview'
        $r.Output | Should -Match 'Removed'
        # The clean actually deleted the card contents (but not the root).
        (Test-Path (Join-Path $script:root 'oldgame.gb')) | Should -BeFalse
        (Test-Path $script:root) | Should -BeTrue
        Remove-Item $drivesJson -Force -ErrorAction SilentlyContinue
    }

    It 'aborts (no summary) when the user declines to continue on a non-empty card' {
        'user data' | Set-Content (Join-Path $script:root 'mygame.gb')
        # first prompt is the non-empty "Continue?" -> n  (declines -> early return)
        $r = Invoke-Wizard -Answers @('n') -WizardArgs @('-TestMode', '-Root', $script:root, '-DryRun')
        $r.Output | Should -Match 'Card is NOT empty'
        $r.Output | Should -Not -Match '=== 8. Summary ==='
    }
}
