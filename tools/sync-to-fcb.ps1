<#
================================================================================
 sync-to-fcb.ps1
 Mirrors this clone of flink-on-k8s-with-cp (on the fcb-flink-cp branch)
 into the FCB Azure DevOps DAH.Kafka.OS clone, using Windows Robocopy.

 HOW TO USE (PowerShell ISE)
   1. Open this file in PowerShell ISE on the FCB-issued Windows laptop.
   2. In the CONFIG block below, edit:
        - $Source        path to your flink-on-k8s-with-cp clone
        - $Destination   path to your DAH.Kafka.OS clone
        - $DryRun        leave $true on the first run; flip to $false to apply
   3. Press F5 with $DryRun = $true. Read the output. Look for any
      '*EXTRA File' / '*EXTRA Dir' lines — those are files that /MIR will
      DELETE in the destination on a real run. If anything FCB-only is listed
      that should NOT be deleted, add it to $excludeDirs or $excludeFiles
      below before applying.
   4. Set $DryRun = $false and press F5 again to actually mirror.
   5. Then on the FCB side:
        cd $Destination
        git status
        git diff --stat
        git diff
        # if it all looks right:
        git add .
        git commit -m "..."
        git push

 WHY ROBOCOPY (not rsync)
   The FCB-issued laptop is Windows. Git Bash on Windows doesn't ship rsync,
   and installing tools on a corporate machine is friction. Robocopy is
   built into Windows since Vista and /MIR is a clean equivalent to
   `rsync -a --delete`. Robocopy exit codes 0-7 are all success states
   (0 = nothing changed, 1 = files copied, 2 = extras, etc.); only >= 8
   indicates a real failure.

 FCB-ONLY FILES
   If DAH.Kafka.OS contains files that are NOT in flink-on-k8s-with-cp
   (e.g. an .azuredevops/ pipeline definition managed by the FCB platform
   team), they will appear in the dry-run as '*EXTRA File / *EXTRA Dir' and
   /MIR will delete them on -Apply. Add their names to $excludeDirs or
   $excludeFiles below BEFORE running with $DryRun = $false.
================================================================================
#>

# =============================================================================
# CONFIG — edit these three for your environment, then press F5
# =============================================================================

$Source      = "C:\path\to\flink-on-k8s-with-cp"   # GitHub clone (on fcb-flink-cp branch)
$Destination = "C:\path\to\DAH.Kafka.OS"           # FCB Azure DevOps clone
$DryRun      = $true                                # $true = preview only; $false = actually copy

# =============================================================================
# Excludes — adjust if FCB-only files exist in the destination
# =============================================================================
# .git/         each repo has its own history; never copy across
# .github/      GitHub-only CI / templates; not relevant to Azure DevOps
# docs/         upward channel for FCB-side errors/screenshots; don't echo back
# node_modules/ defensive; nothing tracked uses it but skip if it appears
# error.txt     same intent as docs/ — FCB pipeline output shared up to GitHub

$excludeDirs  = @('.git', '.github', 'docs', 'node_modules')
$excludeFiles = @('error.txt')

# =============================================================================
# Logic — usually no need to edit below this line
# =============================================================================

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    Write-Host "Source directory not found: $Source" -ForegroundColor Red
    Write-Host 'Edit $Source in the CONFIG block at the top of this script.' -ForegroundColor Yellow
    return
}
if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    Write-Host "Destination directory not found: $Destination" -ForegroundColor Red
    Write-Host 'Edit $Destination in the CONFIG block at the top of this script.' -ForegroundColor Yellow
    return
}

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
if ($DryRun) { $rcArgs += '/L' }   # /L = list only (dry-run)

$mode = if ($DryRun) { 'DRY-RUN  (set $DryRun = $false to actually copy)' } else { 'APPLY' }

Write-Host ''
Write-Host "Source:      $Source"
Write-Host "Destination: $Destination"
Write-Host "Mode:        $mode"
Write-Host ''

& robocopy @rcArgs
$rc = $LASTEXITCODE

# Robocopy exit codes: 0-7 are success states; >= 8 is a real failure.
if ($rc -ge 8) {
    Write-Host ''
    Write-Host "Robocopy returned $rc — see https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility" -ForegroundColor Red
    return
}

Write-Host ''
if ($DryRun) {
    Write-Host 'Dry-run complete.' -ForegroundColor Yellow
    Write-Host "Inspect any '*EXTRA File' / '*EXTRA Dir' lines above — those are files /MIR will DELETE in the destination on a real run." -ForegroundColor Yellow
    Write-Host 'If anything FCB-only appears, add it to $excludeDirs or $excludeFiles in this script before flipping $DryRun = $false.' -ForegroundColor Yellow
} else {
    Write-Host "Sync complete (robocopy exit code $rc)." -ForegroundColor Green
    Write-Host ''
    Write-Host "Next steps in $Destination :" -ForegroundColor Green
    Write-Host '    git status' -ForegroundColor Green
    Write-Host '    git diff --stat' -ForegroundColor Green
    Write-Host '    git diff' -ForegroundColor Green
    Write-Host '    # if everything looks right:' -ForegroundColor Green
    Write-Host '    git add .' -ForegroundColor Green
    Write-Host '    git commit -m "..."' -ForegroundColor Green
    Write-Host '    git push' -ForegroundColor Green
}
