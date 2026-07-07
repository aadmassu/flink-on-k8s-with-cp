$base = 'https://text.psyncopate.io'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$resp = Invoke-RestMethod -Uri "$base/api/text" -Method Get

$text = if ($resp -is [string]) { $resp } elseif ($null -ne $resp.text) { $resp.text } else { ($resp | ConvertTo-Json -Compress) }

Set-Clipboard -Value $text

Write-Host ("Clipboard now holds {0} chars ({1}/api/text)" -f $text.Length, $base)
