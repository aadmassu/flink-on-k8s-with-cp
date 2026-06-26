Add-Type -AssemblyName System.Web
$path    = 'C:\git-repos\flink-on-k8s-with-cp\project-docs\dump.txt'
$text    = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
$escaped = [System.Web.HttpUtility]::JavaScriptStringEncode($text)
$json    = '{"text":"' + $escaped + '"}'
$body    = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod -Uri 'https://text.psyncopate.io/api/text' -Method Post `
  -ContentType 'application/json; charset=utf-8' `
  -Body $body
