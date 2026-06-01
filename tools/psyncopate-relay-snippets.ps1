# PowerShell snippets for the FCB-laptop ↔ Mac file relay.
# Reference only — not a runnable script. Paste the bits you need at the prompt.

# Upload TEXT (current flow — unchanged):
$t = [string](Get-Content -Raw -Path 'C:\git-repos\flink-on-k8s-with-cp\docs\error.txt')
Invoke-RestMethod -Uri 'https://text.psyncopate.io/api/text' -Method Post `
  -ContentType 'application/json' `
  -Body (@{ text = $t } | ConvertTo-Json -Depth 5)

# Upload TEXT (robust — use this when the simple version returns
# {"error": "invalid json"}). Handles tabs, ANSI escape codes, NUL
# bytes, multi-byte UTF-8 — anything `oc` / `kubectl` / build logs
# might emit. Two fixes vs the simple version above:
#   1) JavaScriptStringEncode escapes every control char that PS 5.1's
#      ConvertTo-Json passes through as a raw byte (notably literal tab).
#   2) Body is sent as raw UTF-8 bytes with explicit charset, so PS 5.1
#      doesn't re-encode it as Windows-1252 on the wire.
Add-Type -AssemblyName System.Web
$path    = 'C:\git-repos\flink-on-k8s-with-cp\docs\error.txt'
$text    = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
$escaped = [System.Web.HttpUtility]::JavaScriptStringEncode($text)
$json    = '{"text":"' + $escaped + '"}'
$body    = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod -Uri 'https://text.psyncopate.io/api/text' -Method Post `
  -ContentType 'application/json; charset=utf-8' `
  -Body $body

# Upload a FILE (PDF, tarball, whatever):
$path = 'C:\git-repos\flink-on-k8s-with-cp\artifacts\bundle.tar.gz'
$name = [System.IO.Path]::GetFileName($path)

$u = (Invoke-RestMethod -Uri 'https://text.psyncopate.io/api/files/upload-url' `
       -Method Post -ContentType 'application/json' `
       -Body (@{ name = $name } | ConvertTo-Json)).url

Invoke-WebRequest -Uri $u -Method Put -InFile $path -ContentType 'application/octet-stream'

# Download TEXT:
(Invoke-RestMethod -Uri 'https://text.psyncopate.io/api/text').text |
  Set-Content -Path .\error.txt -Encoding UTF8

# Download a FILE by name:
$name = 'bundle.tar.gz'
$u = (Invoke-RestMethod -Uri ("https://text.psyncopate.io/api/files/download-url?name=" + [uri]::EscapeDataString($name))).url
Invoke-WebRequest -Uri $u -OutFile (".\" + $name)

# List what's currently stored:
(Invoke-RestMethod -Uri 'https://text.psyncopate.io/api/files').files |
  Select-Object name, size, lastModified | Format-Table
