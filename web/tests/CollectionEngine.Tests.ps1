$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('romchecker-collection-engine-' + [guid]::NewGuid().ToString('N'))
$oldApp = $env:APPDATA; $oldXdg = $env:XDG_CONFIG_HOME
$passed = 0
function Assert([bool]$value, [string]$message) {
    if (-not $value) { throw "FAILED: $message" }
    $script:passed++
}
try {
    $library = Join-Path $root 'library'; $data = Join-Path $root 'data'; $job = Join-Path $root 'job'
    foreach ($directory in $library, $data, $job) { [void][IO.Directory]::CreateDirectory($directory) }
    $env:APPDATA = Join-Path $data 'config'; $env:XDG_CONFIG_HOME = $env:APPDATA
    $rom = New-Object byte[] 40976
    $rom[0]=0x4e; $rom[1]=0x45; $rom[2]=0x53; $rom[3]=0x1a; $rom[4]=2; $rom[5]=1
    [IO.File]::WriteAllBytes((Join-Path $library 'Fixture.nes'), $rom)
    $requestPath = Join-Path $job 'request.json'
    [IO.File]::WriteAllText($requestPath, (@{ Action='detect'; Feature='Collections'; Root=$library; DataDirectory=$data; Settings=@{} } | ConvertTo-Json))
    . (Join-Path $PSScriptRoot '..\engine\Invoke-WebJob.ps1') -RequestPath $requestPath
    Assert ($script:OnlineCachePath -eq (Join-Path $data 'engine\online-cache.json')) 'Web runner relocates the cache with its data directory'
    $script:OnlineCache = @{ 'hh2:fixture' = @{ Status='Found'; Name='Fixture'; Date=(Get-Date).ToString('s') } }
    Save-OnlineCache
    Assert ([IO.File]::Exists($script:OnlineCachePath)) 'Online cache persists without relying on the original config directory'
    $script:OnlineCache = $null
    Assert ((Get-Cached 'hh2:fixture').Name -eq 'Fixture') 'A fresh in-memory cache reuses the saved lookup'
    foreach ($con in $script:Consoles) {
        $row = New-Result ([IO.FileInfo]::new((Join-Path $library 'Fixture.nes')))
        $row.Console = $con.Key; $row.Header = 'Invalid'; $row.CheckedUtc = [DateTime]::UtcNow.ToString('o')
        $row.DatMatch = 'Known homebrew'
        $explanation = Get-CollectionExplanation $row
        Assert ($explanation.Contains($con.Name) -and $explanation.Contains('does not prove') -and $explanation.Contains('reference fingerprint matches')) "Console-aware, non-alarmist explanations for $($con.Key)"
    }
    $blocker = Join-Path $root 'not-a-directory'
    [IO.File]::WriteAllText($blocker, 'fixture')
    $script:AppDir = Join-Path $blocker 'child'
    $script:OnlineCachePath = Join-Path $script:AppDir 'online-cache.json'
    $warnings = @(& { Save-OnlineCache; Save-OnlineCache } 3>&1)
    Assert (@($warnings | Where-Object { $_ -is [Management.Automation.WarningRecord] }).Count -eq 1) 'Repeated cache failures produce one actionable warning'
    Assert ($script:ServiceIssues.Count -eq 1) 'Cache failure is retained in structured service issues'
    Write-Host "PASS: $passed collection engine assertions"
}
finally {
    $env:APPDATA = $oldApp; $env:XDG_CONFIG_HOME = $oldXdg
    if ([IO.Directory]::Exists($root)) { [IO.Directory]::Delete($root, $true) }
}
