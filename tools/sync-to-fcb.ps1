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
   3. Press F5. The script ALWAYS runs a dry-run first and prints the deltas.
      Look for any '*EXTRA File' / '*EXTRA Dir' lines — those are files that
      /MIR would DELETE in the destination. If anything FCB-only is listed
      that should NOT be deleted, add it to $excludeDirs / $excludeFiles
      below and answer N at the prompt.
   4. When prompted "Apply these changes? [Y/N]", press Y to actually copy,
      or N to abort.
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
   /MIR will delete them on apply. Add their names to $excludeDirs or
   $excludeFiles below BEFORE answering Y at the prompt.
================================================================================
#>

# =============================================================================
# CONFIG — edit these two for your environment, then press F5
# =============================================================================

$Source      = "C:\git-repos\flink-on-k8s-with-cp"   # GitHub clone (on fcb-flink-cp branch)
$Destination = "C:\git-repos\DAH.Kafka.OS"           # FCB Azure DevOps clone

# =============================================================================
# Excludes — adjust if FCB-only files exist in the destination
# =============================================================================
# .git/         each repo has its own history; never copy across
# .github/      GitHub-only CI / templates; not relevant to Azure DevOps
# docs/         upward channel for FCB-side errors/screenshots; don't echo back
# tools/        local sync helpers (this script); not needed in DAH.Kafka.OS
# node_modules/ defensive; nothing tracked uses it but skip if it appears
# error.txt     same intent as docs/ — FCB pipeline output shared up to GitHub

$excludeDirs  = @('.git', '.github', 'docs', 'tools', 'node_modules')
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

# Build the base robocopy argument list (used by both phases).
$baseArgs = @(
    $Source,
    $Destination,
    '/MIR',     # mirror — purges files in dest not in source
    '/NJH',     # no job header
    '/NJS',     # no job summary
    '/NDL',     # no directory list (less noise)
    '/NP'       # no per-file progress %
)
$baseArgs += '/XD'; $baseArgs += $excludeDirs
$baseArgs += '/XF'; $baseArgs += $excludeFiles

function Invoke-Robocopy {
    param([string[]]$Args, [string]$Phase)

    Write-Host ''
    Write-Host "Source:      $Source"
    Write-Host "Destination: $Destination"
    Write-Host "Mode:        $Phase"
    Write-Host ''

    & robocopy @Args
    $rc = $LASTEXITCODE

    # Robocopy exit codes: 0-7 are success states; >= 8 is a real failure.
    if ($rc -ge 8) {
        Write-Host ''
        Write-Host "Robocopy returned $rc -- see https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility" -ForegroundColor Red
        return $null
    }
    return $rc
}

# ---- Phase 1: ALWAYS dry-run first --------------------------------------------
$dryArgs = $baseArgs + '/L'   # /L = list only
$rc = Invoke-Robocopy -Args $dryArgs -Phase 'DRY-RUN (preview only — nothing copied yet)'
if ($null -eq $rc) { return }

# Robocopy /L: rc=0 means source already matches destination; nothing to do.
if ($rc -eq 0) {
    Write-Host ''
    Write-Host 'Source and destination are already in sync. Nothing to do.' -ForegroundColor Green
    return
}

Write-Host ''
Write-Host "Dry-run complete (robocopy exit code $rc)." -ForegroundColor Yellow
Write-Host "Inspect any '*EXTRA File' / '*EXTRA Dir' lines above -- those are files /MIR will DELETE on apply." -ForegroundColor Yellow
Write-Host 'If anything FCB-only is listed for deletion, abort and add it to $excludeDirs / $excludeFiles before re-running.' -ForegroundColor Yellow
Write-Host ''

# ---- Phase 2: prompt before applying ------------------------------------------
$response = Read-Host 'Apply these changes? [Y/N]'
if ($response -notmatch '^[Yy]$') {
    Write-Host ''
    Write-Host 'Aborted. No files were copied.' -ForegroundColor Yellow
    return
}

$applyRc = Invoke-Robocopy -Args $baseArgs -Phase 'APPLY (mirroring source -> destination)'
if ($null -eq $applyRc) { return }

Write-Host ''
Write-Host "Sync complete (robocopy exit code $applyRc)." -ForegroundColor Green
Write-Host ''
Write-Host "Next steps in $Destination :" -ForegroundColor Green
Write-Host '    git status' -ForegroundColor Green
Write-Host '    git diff --stat' -ForegroundColor Green
Write-Host '    git diff' -ForegroundColor Green
Write-Host '    # if everything looks right:' -ForegroundColor Green
Write-Host '    git add .' -ForegroundColor Green
Write-Host '    git commit -m "..."' -ForegroundColor Green
Write-Host '    git push' -ForegroundColor Green
