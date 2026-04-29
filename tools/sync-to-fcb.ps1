<#
.SYNOPSIS
  Sync the fcb-flink-cp branch of flink-on-k8s-with-cp into the FCB Azure
  DevOps DAH.Kafka.OS clone on a Windows / FCB-issued laptop.

.DESCRIPTION
  Wraps Robocopy /MIR with the right excludes so .git, GitHub-only metadata,
  and shared error/log artifacts under docs/ don't bleed across the two
  repositories. Each repo has its own git history; this script syncs only
  working-tree content.

  Default behavior is a dry-run. Pass -Apply to actually copy.

  Configure paths once via environment variables:
      [Environment]::SetEnvironmentVariable('SYNC_FCB_SOURCE', 'C:\repos\flink-on-k8s-with-cp', 'User')
      [Environment]::SetEnvironmentVariable('SYNC_FCB_DEST',   'C:\repos\DAH.Kafka.OS',         'User')
  ...or pass them inline with -Source / -Destination on every run.

.PARAMETER Source
  Path to the local flink-on-k8s-with-cp clone (must be on fcb-flink-cp branch
  before running). Defaults to $env:SYNC_FCB_SOURCE.

.PARAMETER Destination
  Path to the local DAH.Kafka.OS clone. Defaults to $env:SYNC_FCB_DEST.

.PARAMETER Apply
  Without this switch, the script does a dry-run and prints what would change.
  Pass -Apply to actually copy.

.EXAMPLE
  .\tools\sync-to-fcb.ps1
  Dry-run using paths from environment variables.

.EXAMPLE
  .\tools\sync-to-fcb.ps1 -Apply
  Actually sync.

.EXAMPLE
  .\tools\sync-to-fcb.ps1 -Source C:\repos\flink-on-k8s-with-cp -Destination C:\repos\DAH.Kafka.OS -Apply
  Override paths inline.

.NOTES
  /MIR will delete files in the destination that don't exist in the source.
  ALWAYS review the dry-run output for *EXTRA File / *EXTRA Dir lines before
  running with -Apply. If anything FCB-only is listed for deletion, add it to
  the exclude lists below.
#>
[CmdletBinding()]
param(
    [string]$Source      = $env:SYNC_FCB_SOURCE,
    [string]$Destination = $env:SYNC_FCB_DEST,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

if (-not $Source -or -not $Destination) {
    Write-Host @"

Set both source and destination paths.

Inline (one-off):
    .\tools\sync-to-fcb.ps1 -Source C:\repos\flink-on-k8s-with-cp -Destination C:\repos\DAH.Kafka.OS

Or set persistent environment variables once:
    [Environment]::SetEnvironmentVariable('SYNC_FCB_SOURCE', 'C:\repos\flink-on-k8s-with-cp', 'User')
    [Environment]::SetEnvironmentVariable('SYNC_FCB_DEST',   'C:\repos\DAH.Kafka.OS',         'User')

"@ -ForegroundColor Yellow
    exit 2
}

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    Write-Error "Source directory not found: $Source"
    exit 2
}
if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    Write-Error "Destination directory not found: $Destination"
    exit 2
}

# Excludes:
#   .git/        each repo has its own history; never copy across.
#   .github/     GitHub-only CI; not relevant to Azure DevOps.
#   docs/        upward channel for FCB-side errors/screenshots flowing INTO
#                GitHub; don't echo it back down to DAH.Kafka.OS.
#   node_modules/  defensive; nothing tracked uses it but skip if it appears.
#   error.txt    same intent as docs/ — pipeline output shared up to GitHub.
$excludeDirs  = @('.git', '.github', 'docs', 'node_modules')
$excludeFiles = @('error.txt')

$rcArgs = @(
    $Source,
    $Destination,
    '/MIR',     # mirror — purges files in dest not in source
    '/NJH',     # no job header
    '/NJS',     # no job summary
    '/NDL',     # no directory list (less noise)
    '/NP'       # no per-file progress %
)
$rcArgs += '/XD'; $rcArgs += $excludeDirs
$rcArgs += '/XF'; $rcArgs += $excludeFiles
if (-not $Apply) { $rcArgs += '/L' }   # list-only = dry-run

Write-Host ""
Write-Host "Source:      $Source"
Write-Host "Destination: $Destination"
$mode = if ($Apply) { 'APPLY' } else { 'DRY-RUN (pass -Apply to copy)' }
Write-Host "Mode:        $mode"
Write-Host ""

& robocopy @rcArgs
$rc = $LASTEXITCODE

# Robocopy exit codes: 0-7 are all success states (0 = no change, 1 = files
# copied, 2 = extras, etc.). Anything >= 8 is a real failure.
if ($rc -ge 8) {
    Write-Host "Robocopy returned $rc -- see https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility" -ForegroundColor Red
    exit $rc
}

Write-Host ""
if (-not $Apply) {
    Write-Host "Dry-run complete." -ForegroundColor Yellow
    Write-Host "Inspect any '*EXTRA File' / '*EXTRA Dir' lines above -- those are files /MIR will DELETE in the destination on a real run." -ForegroundColor Yellow
    Write-Host "If anything FCB-only appears, add it to the exclude lists in this script before running with -Apply." -ForegroundColor Yellow
} else {
    Write-Host "Sync complete (robocopy exit code $rc)." -ForegroundColor Green
    Write-Host "Next: cd '$Destination'; git status; git diff --stat; review; commit; push to FCB Azure DevOps." -ForegroundColor Green
}

exit 0
