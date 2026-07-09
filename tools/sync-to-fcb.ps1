<#
================================================================================
 sync-to-fcb.ps1  (flink-on-k8s-with-cp)
 Copies an EXPLICIT LIST OF FILES from this repo's clone into its FCB Azure
 DevOps clone using Windows Robocopy.

 WHY FILE-LEVEL (not /MIR folder mirror): this clone and the FCB repo have
 diverged -- each side has files the other should not receive or lose. A
 folder mirror would copy every local extra AND delete every FCB-only file.
 Copying a named file list touches exactly those files and nothing else;
 all other differences between the two repos are ignored.

 BRANCH NOTE: the copy reads the CHECKED-OUT working tree of the source
 clone. The script prints the current git branch before the dry-run --
 check it is the branch whose version you intend to sync (e.g.
 feature/kafka-rest-proxy-authz-test for the Kafka REST Proxy authz probe).

 HOW TO USE (PowerShell ISE)
   1. Open this file in PowerShell ISE on the FCB-issued Windows laptop.
   2. In the source clone, check out the branch you want to sync:
        cd C:\git-repos\flink-on-k8s-with-cp
        git checkout feature/kafka-rest-proxy-authz-test
   3. In the CONFIG block below, edit:
        - $Source        path to your flink-on-k8s-with-cp clone
        - $Destination   path to the FCB clone of this repo (REPO ROOT)
        - $SyncFiles     repo-relative paths of the files to copy
   4. Press F5. The script ALWAYS runs a dry-run first showing exactly
      which files would be copied (New File = not yet at destination,
      Newer/Older = destination version will be overwritten).
   5. When prompted "Apply the copy? [Y/N]", press Y to copy, or
      N (or Enter) to abort.
   6. Then on the FCB side:
        cd $Destination
        git status
        git diff
        # if it looks right:
        git add .
        git commit -m "..."
        git push

 ROBOCOPY EXIT CODES
   0    nothing copied; files already identical
   1    files copied successfully
   2-7  variations of copied/skipped (still success)
   >=8  real failure (access denied, bad path, syntax, etc.)
================================================================================
#>

# =============================================================================
# CONFIG -- edit these for your environment, then press F5
# =============================================================================

$Source      = "C:\git-repos\flink-on-k8s-with-cp"  # GitHub clone (this repo)
$Destination = "C:\git-repos\DAH.Kafka.OS"          # FCB clone of this repo (VERIFY repo name)

# Repo-relative paths of the files to copy. ONLY these files are written at
# the destination; nothing is deleted and no other differences are touched.
$SyncFiles = @(
    '.azure-pipelines\connectivity-test.yaml'   # connectivity tests + Kafka REST Proxy authz probe
)

# =============================================================================
# Logic -- usually no need to edit below this line
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
foreach ($f in $SyncFiles) {
    $srcFile = Join-Path $Source $f
    if (-not (Test-Path -LiteralPath $srcFile -PathType Leaf)) {
        Write-Host "Source file not found: $srcFile" -ForegroundColor Red
        Write-Host 'Check $SyncFiles in the CONFIG block (paths are relative to $Source).' -ForegroundColor Yellow
        return
    }
}

# The copy reads the WORKING TREE -- show which branch that is.
$branch = ''
try { $branch = (& git -C $Source rev-parse --abbrev-ref HEAD 2>$null) } catch { $branch = '(unknown)' }
Write-Host ''
Write-Host 'Source branch to be synced (the copy reads the checked-out working tree):' -ForegroundColor Cyan
Write-Host ("  {0}  ->  branch: {1}" -f $Source, $branch) -ForegroundColor Cyan
Write-Host ''
Write-Host 'Files to copy:' -ForegroundColor Cyan
foreach ($f in $SyncFiles) { Write-Host "  $f" -ForegroundColor Cyan }

function Invoke-RobocopyFile {
    [OutputType([int])]
    param(
        [Parameter(Mandatory=$true)] [string] $RelPath,
        [Parameter(Mandatory=$true)] [bool]   $DryRun
    )

    $srcDir   = Join-Path $Source      (Split-Path $RelPath -Parent)
    $dstDir   = Join-Path $Destination (Split-Path $RelPath -Parent)
    $fileName = Split-Path $RelPath -Leaf

    Write-Host ''
    Write-Host '================================================================================'
    if ($DryRun) {
        Write-Host "FILE ($RelPath)  --  DRY-RUN (nothing will be copied)"
    } else {
        Write-Host "FILE ($RelPath)  --  APPLY"
    }
    Write-Host "Source:      $srcDir\$fileName"
    Write-Host "Destination: $dstDir\$fileName"
    Write-Host '================================================================================'
    Write-Host ''

    # Plain single-file copy: NO /MIR, so nothing at the destination is ever
    # deleted and no other files are considered.
    $rbArgs = @($srcDir, $dstDir, $fileName, '/NDL', '/NP')
    if ($DryRun) { $rbArgs += '/L' }

    # Pipe robocopy's stdout to Out-Host so it lands on the console rather
    # than the function's pipeline output; otherwise the caller's
    # `$rc = Invoke-RobocopyFile ...` captures the lines AND the exit code.
    & robocopy @rbArgs | Out-Host

    return [int]$LASTEXITCODE
}

function Assert-RobocopyOk {
    param([int] $Rc, [string] $Label)
    if ($Rc -ge 8) {
        Write-Host ''
        Write-Host "$Label failed with robocopy exit code $Rc." -ForegroundColor Red
        Write-Host 'See https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility' -ForegroundColor Red
        throw "robocopy failed: $Label (exit $Rc)"
    }
}

# ---- Phase 1: dry-run --------------------------------------------------------
$dryTotal = 0
foreach ($f in $SyncFiles) {
    $rc = Invoke-RobocopyFile -RelPath $f -DryRun $true
    Assert-RobocopyOk -Rc $rc -Label "dry-run ($f)"
    $dryTotal += $rc
}

if ($dryTotal -eq 0) {
    Write-Host ''
    Write-Host '================================================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  ALL SYNCED -- NO FILES TO COPY' -ForegroundColor Green
    Write-Host '  The listed files are already identical at the destination.' -ForegroundColor Green
    Write-Host ''
    Write-Host '================================================================================' -ForegroundColor Green
    return
}

Write-Host ''
Write-Host 'Dry-run complete. Only the files listed above will be written;' -ForegroundColor Yellow
Write-Host 'nothing at the destination is deleted or otherwise modified.' -ForegroundColor Yellow
Write-Host ''

# ---- Phase 2: prompt before applying ----------------------------------------
$response = Read-Host 'Apply the copy? [Y/N]'
if ($response -notmatch '^[Yy]$') {
    Write-Host ''
    Write-Host 'Aborted. No files were copied.' -ForegroundColor Yellow
    return
}

# ---- Phase 3: apply ----------------------------------------------------------
foreach ($f in $SyncFiles) {
    $rc = Invoke-RobocopyFile -RelPath $f -DryRun $false
    Assert-RobocopyOk -Rc $rc -Label "apply ($f)"
}

Write-Host ''
Write-Host 'Copy complete.' -ForegroundColor Green
Write-Host ''
Write-Host "Next steps in $Destination :" -ForegroundColor Green
Write-Host '    git status' -ForegroundColor Green
Write-Host '    git diff' -ForegroundColor Green
Write-Host '    # expect ONLY the listed file(s) changed; if so:' -ForegroundColor Green
Write-Host '    git add .azure-pipelines/connectivity-test.yaml' -ForegroundColor Green
Write-Host '    git commit -m "connectivity-test: add Kafka REST Proxy authz probe (dev)"' -ForegroundColor Green
Write-Host '    git push' -ForegroundColor Green
