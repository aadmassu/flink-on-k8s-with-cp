<#
================================================================================
 sync-to-fcb.ps1
 Mirrors this clone of flink-on-k8s-with-cp (on the fcb-flink-cp branch)
 into the FCB Azure DevOps DAH.Kafka.OS clone, using Windows Robocopy.

 The mirror covers everything tracked at the repo root including docs/
 (proposals, weekly reports, issue tracker, lessons-learned, REST-proxy
 design docs). The local-only project-docs/ directory is excluded from
 the /MIR pass; only project-docs/dump.txt is copied across as a single
 walking-artifact file. Everything else under project-docs/ (vendor PDFs,
 screenshots, ROSA notes, pump.txt) stays local.

 HOW TO USE (PowerShell ISE)
   1. Open this file in PowerShell ISE on the FCB-issued Windows laptop.
   2. In the CONFIG block below, edit:
        - $Source        path to your flink-on-k8s-with-cp clone
        - $Destination   path to your DAH.Kafka.OS clone
   3. Press F5. The script ALWAYS runs a dry-run first, prints the deltas
      and the robocopy summary table (file/byte counts), and previews the
      project-docs/dump.txt single-file passthrough.
      Look for any '*EXTRA File' / '*EXTRA Dir' lines — those are files that
      /MIR would DELETE in the destination. If anything FCB-only is listed
      that should NOT be deleted, answer N at the prompt and add it to
      $excludeDirs / $excludeFiles below before re-running.
   4. When prompted "Apply these changes? [Y/N]", press Y to actually copy,
      or N (or Enter) to abort.
   5. Then on the FCB side:
        cd $Destination
        git status
        git diff --stat
        git diff
        # if it all looks right:
        git add .
        git commit -m "..."
        git push

 ROBOCOPY EXIT CODES
   0    nothing copied; source and destination already in sync
   1    files copied successfully
   2    extra files / dirs detected (and removed by /MIR)
   3    1 + 2 (typical for a successful mirror with deletions)
   4-7  some skipped or mismatched files (still success)
   >=8  real failure (access denied, bad path, syntax, etc.)
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
# project-docs/ local-only scratch area (vendor PDFs, screenshots, ROSA notes,
#                pump.txt). Excluded from the /MIR pass; project-docs/dump.txt
#                is the one file copied across after the mirror — see the
#                "dump.txt one-file passthrough" block in Phase 2 below.
# tools/        local sync helpers (this script); not needed in DAH.Kafka.OS
# node_modules/ defensive; nothing tracked uses it but skip if it appears
# .gitattributes routes *.tar through Git LFS, which the destination Azure DevOps
#                Repos server does NOT support (push fails with
#                "Could not find a Command Extension for Command:git-lfs-authenticate").
#                Excluding it means tar files are committed on the destination
#                as regular large files (Azure DevOps Repos accepts those).

$excludeDirs  = @('.git', '.github', 'project-docs', 'tools', 'node_modules')
$excludeFiles = @('.gitattributes')

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

# Build robocopy args.
#   /MIR  mirror source -> dest (purges files in dest not in source)
#   /NDL  no per-directory listing (less noise)
#   /NP   no per-file progress %
#   (We INTENTIONALLY do NOT use /NJH or /NJS — we want the start banner and
#    end-of-job summary table with file and byte counts.)
$baseArgs = @(
    $Source,
    $Destination,
    '/MIR',
    '/NDL',
    '/NP'
)
$baseArgs += '/XD'; $baseArgs += $excludeDirs
$baseArgs += '/XF'; $baseArgs += $excludeFiles

# ---- Phase 1: ALWAYS dry-run first --------------------------------------------
Write-Host ''
Write-Host '================================================================================'
Write-Host "PHASE 1 -- DRY-RUN  (nothing will be copied)"
Write-Host "Source:      $Source"
Write-Host "Destination: $Destination"
Write-Host '================================================================================'
Write-Host ''

& robocopy @baseArgs '/L'   # /L = list only
$dryRc = $LASTEXITCODE

if ($dryRc -ge 8) {
    Write-Host ''
    Write-Host "Robocopy dry-run failed with exit code $dryRc." -ForegroundColor Red
    Write-Host 'See https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility' -ForegroundColor Red
    return
}

if ($dryRc -eq 0) {
    Write-Host ''
    Write-Host 'Source and destination are already in sync. Nothing to do.' -ForegroundColor Green
    return
}

Write-Host ''
Write-Host "Dry-run complete (robocopy exit code $dryRc; review the summary table above)." -ForegroundColor Yellow
Write-Host "Inspect any '*EXTRA File' / '*EXTRA Dir' lines -- those are files /MIR will DELETE on apply." -ForegroundColor Yellow
Write-Host 'If anything FCB-only is listed for deletion, answer N and add it to $excludeDirs / $excludeFiles before re-running.' -ForegroundColor Yellow
Write-Host ''

# project-docs/dump.txt one-file passthrough -- dry-run preview
$dumpSrc = Join-Path $Source 'project-docs\dump.txt'
$dumpDst = Join-Path $Destination 'project-docs\dump.txt'
if (Test-Path -LiteralPath $dumpSrc -PathType Leaf) {
    Write-Host 'project-docs/dump.txt passthrough (will be copied after the mirror):' -ForegroundColor Yellow
    Write-Host "    $dumpSrc"
    Write-Host "    -> $dumpDst"
} else {
    Write-Host "Note: $dumpSrc does not exist; dump.txt passthrough will be a no-op." -ForegroundColor Yellow
}
Write-Host ''

# ---- Phase 2: prompt before applying ------------------------------------------
$response = Read-Host 'Apply these changes? [Y/N]'
if ($response -notmatch '^[Yy]$') {
    Write-Host ''
    Write-Host 'Aborted. No files were copied.' -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host '================================================================================'
Write-Host "PHASE 2 -- APPLY  (mirroring source -> destination)"
Write-Host "Source:      $Source"
Write-Host "Destination: $Destination"
Write-Host '================================================================================'
Write-Host ''

& robocopy @baseArgs   # no /L this time -> actually copies
$applyRc = $LASTEXITCODE

if ($applyRc -ge 8) {
    Write-Host ''
    Write-Host "Robocopy apply failed with exit code $applyRc." -ForegroundColor Red
    Write-Host 'See https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility' -ForegroundColor Red
    return
}

# project-docs/dump.txt one-file passthrough -- apply
# The /MIR pass above excludes project-docs/ entirely. dump.txt is the one
# walking-artifact file (e.g. proposals to walk with FCB ops) that needs to
# reach DAH.Kafka.OS, so copy it now. Everything else under project-docs/
# (vendor PDFs, screenshots, ROSA notes, pump.txt) stays local.
if (Test-Path -LiteralPath $dumpSrc -PathType Leaf) {
    $dumpDstDir = Split-Path -Parent $dumpDst
    if (-not (Test-Path -LiteralPath $dumpDstDir -PathType Container)) {
        New-Item -Path $dumpDstDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $dumpSrc -Destination $dumpDst -Force
    Write-Host ''
    Write-Host "Copied project-docs/dump.txt -> $dumpDst" -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host "Note: $dumpSrc does not exist; dump.txt passthrough skipped." -ForegroundColor Yellow
}

Write-Host ''
Write-Host "Sync complete (robocopy exit code $applyRc; review the summary table above)." -ForegroundColor Green
Write-Host ''
Write-Host "Next steps in $Destination :" -ForegroundColor Green
Write-Host '    git status' -ForegroundColor Green
Write-Host '    git diff --stat' -ForegroundColor Green
Write-Host '    git diff' -ForegroundColor Green
Write-Host '    # if everything looks right:' -ForegroundColor Green
Write-Host '    git add .' -ForegroundColor Green
Write-Host '    git commit -m "..."' -ForegroundColor Green
Write-Host '    git push' -ForegroundColor Green
