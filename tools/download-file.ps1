# Download a file by name into the local Downloads folder (Windows + macOS).
# Overwrites the file if it already exists.
$name = 'dump.txt'

$base = 'https://text.psyncopate.io'

if ([string]::IsNullOrWhiteSpace($name)) {
    throw "Set `$name to the file name shown in the Files list."
}

# Downloads folder for the current user on both Windows and macOS.
$downloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
if (-not (Test-Path -LiteralPath $downloads)) {
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null
}
$dest = Join-Path $downloads $name

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = "$base/api/files/download?name=" + [Uri]::EscapeDataString($name)

try {
    # -OutFile overwrites an existing file. -UseBasicParsing keeps Windows PowerShell 5.1 happy.
    Invoke-WebRequest -Uri $url -Method Get -OutFile $dest -UseBasicParsing -ErrorAction Stop
} catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($status -eq 404) { throw "File not found on server: $name" }
    throw "Download failed for $name : $($_.Exception.Message)"
}

$size = (Get-Item -LiteralPath $dest).Length
Write-Host ("Downloaded {0} ({1} bytes) -> {2}" -f $name, $size, $dest)
