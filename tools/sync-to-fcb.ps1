<#
================================================================================
 sync-to-fcb.ps1  (flink-on-k8s-with-cp)
 Mirrors this infra repo's content into its FCB Azure DevOps clone using
 Windows Robocopy. Modeled on psy-fcb-flink-jobs/tools/sync-to-fcb.ps1.

   <source>/                         (this repo)
   |-- .azure-pipelines/             <- connectivity-test pipeline + templates
   |-- apps/                         <- CMF / app helm values      (optional sync)
   |-- charts/                       <- helm charts                (optional sync)
   |-- openshift-prereqs/            <- cluster prereq manifests   (optional sync)
   |-- docs/                         <- notes (NOT synced)
   |-- tools/                        <- this script (NOT synced)
   `-- README.md                     <- repo overview (NOT synced)

   <destination>/                    (FCB Azure DevOps clone)
   |-- .azure-pipelines/             <- receives mirror of source's pipelines
   |-- <folders not in $SyncFolders> <- owned at destination; LEFT ALONE
   `-- README.md                     <- owned at destination; LEFT ALONE

 The script runs one targeted /MIR per folder in $SyncFolders rather than a
 root-level mirror, so destination-only folders and the root README are
 never touched.

 BRANCH NOTE: Robocopy copies whatever is CHECKED OUT in the source clone's
 working tree. The script prints the current git branch before the dry-run --
 check it is the branch you intend to sync (e.g.
 feature/kafka-rest-proxy-authz-test for the Kafka REST Proxy authz probe).

 HOW TO USE (PowerShell ISE)
   1. Open this file in PowerShell ISE on the FCB-issued Windows laptop.
   2. In the source clone, check out the branch you want to sync:
        cd C:\git-repos\flink-on-k8s-with-cp
        git checkout feature/kafka-rest-proxy-authz-test
   3. In the CONFIG block below, edit:
        - $Source        path to your flink-on-k8s-with-cp clone
        - $Destination   path to the FCB clone of this repo (REPO ROOT)
        - $SyncFolders   folders to mirror (default: .azure-pipelines only)
   4. Press F5. The script ALWAYS runs a dry-run first, printing deltas and
      the robocopy summary tables. Look for '*EXTRA File' / '*EXTRA Dir'
      lines -- those are files /MIR would DELETE in the destination. If
      anything FCB-only is listed that should NOT be deleted, answer N and
      add it to $excludeDirs / $excludeFiles before re-running.
   5. When prompted "Apply the mirror(s)? [Y/N]", press Y to copy, or
      N (or Enter) to abort.
   6. Then on the FCB side:
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
# CONFIG -- edit these for your environment, then press F5
# =============================================================================

$Source      = "C:\git-repos\flink-on-k8s-with-cp"  # GitHub clone (this repo)
$Destination = "C:\git-repos\DAH.Kafka.OS"          # FCB clone of this repo (VERIFY repo name)

# Folders to mirror, one targeted /MIR each. Default is only the pipelines
# folder (carries the connectivity-test pipeline + Kafka REST Proxy authz
# probe). Uncomment others once their FCB-side layout is confirmed.
$SyncFolders = @(
    '.azure-pipelines'
    # 'apps'
    # 'charts'
    # 'openshift-prereqs'
)

# =============================================================================
# Excludes -- applied to every mirror operation
# =============================================================================
# .git/         each repo has its own history; never copy across
# .github/      GitHub-only CI / templates; not relevant to Azure DevOps
# .vscode/      editor settings local to this checkout
# node_modules/ defensive; nothing tracked uses it but skip if it appears
# error.txt     defensive: stray error capture
# .DS_Store     macOS Finder metadata

$excludeDirs  = @('.git', '.github', '.vscode', 'node_modules')
$excludeFiles = @('error.txt', '.DS_Store')

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
foreach ($sf in $SyncFolders) {
    $srcCheck = Join-Path $Source $sf
    if (-not (Test-Path -LiteralPath $srcCheck -PathType Container)) {
        Write-Host "Source folder not found: $srcCheck" -ForegroundColor Red
        return
    }
}

# Robocopy copies the WORKING TREE -- show which branch that is.
$branch = ''
try { $branch = (& git -C $Source rev-parse --abbrev-ref HEAD 2>$null) } catch { $branch = '(unknown)' }
Write-Host ''
Write-Host "Source branch to be synced (robocopy copies the checked-out working tree):" -ForegroundColor Cyan
Write-Host ("  {0}  ->  branch: {1}" -f $Source, $branch) -ForegroundColor Cyan

# Build the shared robocopy arg tail.
#   /MIR  mirror source -> dest (purges files in dest not in source)
#   /NDL  no per-directory listing (less noise)
#   /NP   no per-file progress %
#   We INTENTIONALLY do NOT use /NJH or /NJS -- we want the start banner and
#   end-of-job summary table.
$argTail = @('/MIR', '/NDL', '/NP', '/XD') + $excludeDirs + @('/XF') + $excludeFiles

function Invoke-Robocopy {
    [OutputType([int])]
    param(
        [Parameter(Mandatory=$true)] [string]   $Src,
        [Parameter(Mandatory=$true)] [string]   $Dst,
        [Parameter(Mandatory=$true)] [string[]] $Tail,
        [Parameter(Mandatory=$true)] [bool]     $DryRun,
        [Parameter(Mandatory=$true)] [string]   $Label
    )

    Write-Host ''
    Write-Host '================================================================================'
    if ($DryRun) {
        Write-Host "$Label  --  DRY-RUN (nothing will be copied)"
    } else {
        Write-Host "$Label  --  APPLY (mirroring source -> destination)"
    }
    Write-Host "Source:      $Src"
    Write-Host "Destination: $Dst"
    Write-Host '================================================================================'
    Write-Host ''

    # NOTE: $args is an automatic variable in PowerShell -- use $rbArgs.
    $rbArgs = @($Src, $Dst) + $Tail
    if ($DryRun) { $rbArgs += '/L' }

    # Pipe robocopy's stdout to Out-Host so it lands on the console rather than
    # the function's pipeline output. Otherwise the caller's `$rc = Invoke-Robocopy ...`
    # captures the streamed lines AND the exit code as an Object[] instead of [int].
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

# ---- Phase 1: dry-run ALL operations -----------------------------------------
$dryTotal = 0
foreach ($sf in $SyncFolders) {
    $rc = Invoke-Robocopy -Src (Join-Path $Source $sf) -Dst (Join-Path $Destination $sf) `
            -Tail $argTail -DryRun $true -Label "FOLDER ($sf)"
    Assert-RobocopyOk -Rc $rc -Label "dry-run ($sf)"
    $dryTotal += $rc
}

if ($dryTotal -eq 0) {
    Write-Host ''
    Write-Host '================================================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  ALL SYNCED -- NO FILES TO COPY' -ForegroundColor Green
    Write-Host '  Source and destination are already in sync. Nothing to do.' -ForegroundColor Green
    Write-Host ''
    Write-Host '================================================================================' -ForegroundColor Green
    return
}

Write-Host ''
Write-Host "Dry-run summary:" -ForegroundColor Yellow
Write-Host "  folders ($($SyncFolders -join ', ')): combined exit $dryTotal"
Write-Host "Inspect any '*EXTRA File' / '*EXTRA Dir' lines above -- /MIR will DELETE those on apply." -ForegroundColor Yellow
Write-Host 'If anything FCB-only is listed for deletion, answer N and add it to $excludeDirs / $excludeFiles before re-running.' -ForegroundColor Yellow
Write-Host ''

# ---- Phase 2: prompt before applying ----------------------------------------
$response = Read-Host 'Apply the mirror(s)? [Y/N]'
if ($response -notmatch '^[Yy]$') {
    Write-Host ''
    Write-Host 'Aborted. No files were copied.' -ForegroundColor Yellow
    return
}

# ---- Phase 3: apply ALL operations -------------------------------------------
$applyTotal = 0
foreach ($sf in $SyncFolders) {
    $rc = Invoke-Robocopy -Src (Join-Path $Source $sf) -Dst (Join-Path $Destination $sf) `
            -Tail $argTail -DryRun $false -Label "FOLDER ($sf)"
    Assert-RobocopyOk -Rc $rc -Label "apply ($sf)"
    $applyTotal += $rc
}

Write-Host ''
Write-Host "Sync complete (folders combined exit $applyTotal)." -ForegroundColor Green
Write-Host ''
Write-Host "Next steps in $Destination :" -ForegroundColor Green
Write-Host '    git status' -ForegroundColor Green
Write-Host '    git diff --stat' -ForegroundColor Green
Write-Host '    git diff' -ForegroundColor Green
Write-Host '    # if everything looks right:' -ForegroundColor Green
Write-Host '    git add .' -ForegroundColor Green
Write-Host '    git commit -m "..."' -ForegroundColor Green
Write-Host '    git push' -ForegroundColor Green
