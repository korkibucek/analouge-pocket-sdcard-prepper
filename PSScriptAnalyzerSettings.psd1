@{
    # Run all default rules except those that are intentionally not applicable here.
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # This is an interactive CLI/console tool: Write-Host is the correct way to
        # render the wizard and server banners to the user.
        'PSAvoidUsingWriteHost',

        # The engine uses an explicit, well-tested -DryRun model for state-changing
        # functions rather than [CmdletBinding(SupportsShouldProcess)]. Adding
        # ShouldProcess across the API would change every call site for no real gain.
        'PSUseShouldProcessForStateChangingFunctions',

        # MD5 is REQUIRED, not chosen for security: Analogue publishes MD5 checksums
        # for Pocket firmware, so we must compare against MD5 to validate downloads.
        # See src/PocketPrep/Private/Get-PocketMd5.ps1 and docs/manifests.md.
        'PSAvoidUsingBrokenHashAlgorithms'
    )
}
