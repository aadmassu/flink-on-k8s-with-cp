$path = 'C:\git-repos\flink-on-k8s-with-cp\tools\upload-file.ps1'

$base = 'https://text.psyncopate.io'

if (-not (Test-Path -LiteralPath $path)) {
    throw "File not found: $path"
}

$name = [System.IO.Path]::GetFileName($path)
$size = (Get-Item -LiteralPath $path).Length
if ($size -gt 4MB) {
    Write-Warning ("File is {0:N2} MB — proxy upload caps around 4 MB and may fail." -f ($size / 1MB))
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$b64  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
$body = @{ name = $name; dataB64 = $b64 } | ConvertTo-Json -Compress

$resp = Invoke-RestMethod -Uri "$base/api/files/upload" `
                          -Method Post `
                          -ContentType 'application/json' `
                          -Body $body

Write-Host ("Uploaded {0} ({1} bytes)" -f $resp.name, $resp.size)
