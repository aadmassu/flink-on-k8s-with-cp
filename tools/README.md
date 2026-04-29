# tools/

Helpers for the two-laptop / two-repo workflow.

| Script | Purpose | Where to run |
| --- | --- | --- |
| `sync-to-fcb.ps1` | Mirror this clone (on `fcb-flink-cp` branch) into the FCB Azure DevOps `DAH.Kafka.OS` clone using Robocopy. | FCB-issued **Windows** laptop, in **PowerShell**. |

## sync-to-fcb.ps1 — one-time setup

Set the source and destination paths once so the script can default them:

```powershell
[Environment]::SetEnvironmentVariable('SYNC_FCB_SOURCE', 'C:\repos\flink-on-k8s-with-cp', 'User')
[Environment]::SetEnvironmentVariable('SYNC_FCB_DEST',   'C:\repos\DAH.Kafka.OS',         'User')
```

Open a fresh PowerShell window after setting these (so they're in scope).

## Daily flow

```powershell
# 1. Pick up changes from GitHub
cd $env:SYNC_FCB_SOURCE
git checkout fcb-flink-cp
git pull

# 2. Dry-run the sync — review what would change
.\tools\sync-to-fcb.ps1

# 3. If the dry-run looks right, apply
.\tools\sync-to-fcb.ps1 -Apply

# 4. Inspect on the FCB side and push to Azure DevOps
cd $env:SYNC_FCB_DEST
git status
git diff --stat
git diff
git add .
git commit -m "..."
git push
```

## What gets excluded

`/MIR` mirrors source → destination, but these are deliberately left alone:

| Excluded | Why |
| --- | --- |
| `.git/` | Each repo has its own history. Never overwrite. |
| `.github/` | GitHub Actions / templates — irrelevant to Azure DevOps. |
| `docs/` | Channel for FCB-side errors/screenshots flowing up to GitHub. Don't push it back down. |
| `node_modules/` | Defensive; not tracked, but skip if it ever appears. |
| `error.txt` | Same idea as `docs/` — FCB pipeline output shared up to GitHub. |

If `DAH.Kafka.OS` has any FCB-only files that aren't in this repo (e.g. an `.azuredevops/` pipeline definition the FCB platform team manages), they will appear in the dry-run as `*EXTRA File` / `*EXTRA Dir` and `/MIR` will delete them on `-Apply`. **Add them to the exclude lists in `sync-to-fcb.ps1` before running with `-Apply`.**

## Why Robocopy, not rsync

The FCB-issued laptop is Windows. Git Bash on Windows doesn't ship rsync, and installing it on a locked-down corporate machine is friction we don't need. Robocopy is built in to Windows, has been since Vista, and `/MIR` is a clean equivalent to `rsync -a --delete`.

## Sanity check after every sync

After `-Apply`, in `DAH.Kafka.OS`:
- `git status` — does the changed-file list match what you expected?
- `git diff --stat` — line counts roughly match what was committed on the GitHub side?
- `git diff` — spot-check actual content, especially on YAML and chart values.

If anything looks off, **don't push** — investigate first.
