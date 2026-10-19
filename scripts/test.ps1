# Author: Minoru Yasui
# Assisted-by: Codex:GPT-6.1
<#
.SYNOPSIS
Run source checks and ERT, or ERT alone with -TestOnly.
.EXAMPLE
pwsh -NoProfile -File ./scripts/test.ps1 -Emacs 'C:\Program Files\Emacs\bin\emacs.exe'
#>
[CmdletBinding()]
param(
    [string] $Emacs = $(if ($env:EMACS) { $env:EMACS } else { 'emacs' }),
    [switch] $TestOnly
)

$ErrorActionPreference = 'Stop'
# Preserve Emacs's exit code even when the caller enables native error handling.
$PSNativeCommandUseErrorActionPreference = $false
$emacsArguments = @('-Q', '--batch', '-l', (Join-Path $PSScriptRoot 'run-tests.el'))
if ($TestOnly) {
    $emacsArguments += '--test-only'
}
& $Emacs @emacsArguments
exit $LASTEXITCODE
