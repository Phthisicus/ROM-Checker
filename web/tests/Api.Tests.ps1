param(
    [string]$Dotnet = 'dotnet',
    [string]$PowerShell = $(if ([IO.Path]::DirectorySeparatorChar -eq '\') { 'powershell.exe' } else { 'pwsh' }),
    [string]$ServerDll = (Join-Path $PSScriptRoot '..\server\bin\Debug\net10.0\RomChecker.Web.dll')
)
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('romchecker-api-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$library = Join-Path $root 'library'
$data = Join-Path $root 'data'
[void][IO.Directory]::CreateDirectory($library)
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
$base = "http://127.0.0.1:$port/roms"
$env:ASPNETCORE_URLS = "http://127.0.0.1:$port"
$env:ROMCHECKER_LIBRARY = $library
$env:ROMCHECKER_DATA = $data
$env:ROMCHECKER_ENGINE = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$env:ROMCHECKER_POWERSHELL = $PowerShell
$env:ROMCHECKER_PASSWORD = 'fixture-only-password-not-for-deployment'
$env:ROMCHECKER_PATH_BASE = '/roms'
$env:ROMCHECKER_TRUSTED_PROXIES = ''
$passed = 0
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$headers = @{ 'X-RomChecker' = '1' }
function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw "FAILED: $message" }; $script:passed++
}
function Request([string]$path, [string]$method = 'GET', $body = $null, $customHeaders = $headers) {
    $session.Headers.Clear()
    $parameters = @{ Uri = "$base/api$path"; Method = $method; WebSession = $session
        Headers = $customHeaders; UseBasicParsing = $true }
    if ($null -ne $body) { $parameters.ContentType = 'application/json'; $parameters.Body = ConvertTo-Json -InputObject $body -Depth 12 }
    Invoke-WebRequest @parameters
}
function JsonRequest([string]$path, [string]$method = 'GET', $body = $null) {
    $content = (Request $path $method $body).Content
    if (-not [string]::IsNullOrWhiteSpace($content)) {
        try { $parsed = $content.TrimStart([char]0xfeff) | ConvertFrom-Json; $parsed }
        catch { throw "Invalid JSON response from ${path}: $content" }
    }
}
function ExpectStatus([int]$status, [scriptblock]$action) {
    $actual = 0
    try { $response = & $action; $actual = [int]$response.StatusCode } catch {
        if ($_.Exception.Response) { $actual = [int]$_.Exception.Response.StatusCode } else { throw }
    }
    Assert ($actual -eq $status) "HTTP $status (actual $actual)"
}
function Job([string]$action, $extra = @{}) {
    $request = @{ action = $action }; foreach ($key in $extra.Keys) { $request[$key] = $extra[$key] }
    $job = JsonRequest '/jobs' 'POST' $request
    $until = [DateTime]::UtcNow.AddSeconds(90)
    do {
        Start-Sleep -Milliseconds 200
        $detail = JsonRequest "/jobs/$($job.id)"
    } while ($detail.job.status -in 'queued','running','cancelling' -and [DateTime]::UtcNow -lt $until)
    if ($detail.job.status -notin 'completed','completed-with-warnings') {
        $output = (Request "/jobs/$($job.id)/log").Content
        throw "Job '$action' failed: $($detail.job.error)`n$output"
    }
    return $detail
}
$server = $null
try {
    $server = Start-Process -FilePath $Dotnet -ArgumentList "`"$((Resolve-Path $ServerDll).Path)`"" -PassThru -RedirectStandardOutput (Join-Path $root 'server.log') -RedirectStandardError (Join-Path $root 'server-error.log')
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            [void](Invoke-WebRequest "$base/healthz" -UseBasicParsing -TimeoutSec 2); $ready = $true; break
        } catch { if ($server.HasExited) { throw (Get-Content (Join-Path $root 'server-error.log') -Raw) }; Start-Sleep -Milliseconds 250 }
    }
    Assert $ready 'Server becomes healthy'
    ExpectStatus 401 { Request '/jobs' }
    foreach ($path in '/settings','/catalog','/info','/folders','/jobs/missing/results','/jobs/missing/artifacts/report.html') {
        ExpectStatus 401 { Request $path }
    }
    ExpectStatus 403 { Request '/login' 'POST' @{ password = $env:ROMCHECKER_PASSWORD } @{} }
    ExpectStatus 401 { Request '/login' 'POST' @{ password = 'incorrect' } }
    [void](JsonRequest '/login' 'POST' @{ password = $env:ROMCHECKER_PASSWORD })
    Assert ((JsonRequest '/session').authenticated) 'Cookie authentication works below a subpath'
    $html = (Invoke-WebRequest "$base/" -UseBasicParsing).Content
    Assert ($html -match 'content="/roms"') 'HTML receives the external base path'
    Assert ($html -notmatch '__BASE_PATH__') 'No unresolved base placeholder'
    $asset = [regex]::Match($html, 'src="\./(assets/[^"]+)"').Groups[1].Value
    Assert ((Invoke-WebRequest "$base/$asset" -UseBasicParsing).StatusCode -eq 200) 'Assets load under the base path'
    ExpectStatus 403 { Request '/login' 'POST' @{ password = $env:ROMCHECKER_PASSWORD } @{ 'X-RomChecker' = '1'; 'X-Forwarded-Proto' = 'https'; Origin = "https://127.0.0.1:$port" } }
    ExpectStatus 403 { Request '/settings' 'PUT' @{} @{ 'X-RomChecker' = '1'; Origin = 'https://untrusted.example' } }
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'apply'; confirm = $true; sourceId = '..' } }
    foreach ($jobAction in 'apply','unpack','workflow','undo','cleanup') {
        ExpectStatus 400 { Request '/jobs' 'POST' @{ action = $jobAction } }
    }
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = '..\Organization' } }
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = $null } }
    ExpectStatus 400 { Request '/jobs' 'POST' @{} }
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'scan'; feature = 'Archives' } }
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'undo-preview'; journal = ('..' + [IO.Path]::DirectorySeparatorChar + 'journal.csv') } }
    ExpectStatus 400 { Request '/folders?path=..' }
    $settings = JsonRequest '/settings'
    $settings.defenderScan = $false; $settings.autoDat = $false; $settings.identifyUnknown = $false
    $settings.hasheous = 'Off'; $settings.onlineCheck = 'Off'; $settings.retailOnly = $false
    [void](JsonRequest '/settings' 'PUT' $settings)
    $invalid = $settings | ConvertTo-Json | ConvertFrom-Json
    $invalid.archiveMaxEntries = -1
    ExpectStatus 400 { Request '/settings' 'PUT' $invalid }
    $fixture = New-Object byte[] 40976
    $fixture[0] = 0x4e; $fixture[1] = 0x45; $fixture[2] = 0x53; $fixture[3] = 0x1a; $fixture[4] = 2; $fixture[5] = 1
    $original = Join-Path $library 'Fixture.nes'
    [IO.File]::WriteAllBytes($original, $fixture)
    $scan = Job 'scan'
    $results = JsonRequest "/jobs/$($scan.job.id)/results"
    Assert ($results.total -eq 1) 'Real engine results reach the API'
    Assert ($results.items[0].Console -eq 'NES') 'Engine recognizes the fixture console'
    Assert ($results.items[0].AntivirusStatus -eq 'Disabled') 'Disabled antivirus is explicit'
    Assert ((Request "/jobs/$($scan.job.id)/artifacts/report.html").Content -match 'ROM Sorter report') 'HTML report is downloadable'
    Assert ((Request "/jobs/$($scan.job.id)/artifacts/report.csv").Content -match 'Fixture.nes') 'CSV report is downloadable'
    Assert ([IO.File]::Exists($original)) 'Scanning never moves the ROM'
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'cleanup'; sourceId = $scan.job.id; confirm = $true } }
    Assert ((Request "/jobs/$($scan.job.id)/events").Content -match 'data:') 'Job events use the SSE contract'
    $filtered = JsonRequest "/jobs/$($scan.job.id)/results?q=does-not-exist"
    Assert ($filtered.total -eq 0) 'Result filtering is applied'
    $plan = Job 'plan' @{ sourceId = $scan.job.id; reviews = @(@{ path = $original; decision = 'original' }) }
    $planned = JsonRequest "/jobs/$($plan.job.id)/results"
    $target = $planned.items[0].Target
    Assert (-not [string]::IsNullOrEmpty($target)) 'Preview includes an explicit destination'
    $applied = Job 'apply' @{ sourceId = $plan.job.id; confirm = $true }
    Assert ($applied.summary.Planned -eq 0) 'Completed moves are not counted as still planned'
    Assert ([IO.File]::Exists($target) -and -not [IO.File]::Exists($original)) 'Apply executes the saved plan'
    ExpectStatus 409 { Request '/jobs' 'POST' @{ action = 'apply'; sourceId = $plan.job.id; confirm = $true } }
    $history = Job 'history'
    $journals = @(JsonRequest "/jobs/$($history.job.id)/artifacts/history.json")
    Assert ($journals.Count -ge 1) 'Recovery journals are available'
    [void](Job 'undo-preview' @{ journal = $journals[0].Name })
    [void](Job 'undo' @{ journal = $journals[0].Name; confirm = $true })
    Assert ([IO.File]::Exists($original)) 'Journaled undo restores the original file'
    $stale = Job 'scan'
    [IO.File]::AppendAllText($original, 'changed')
    $failed = JsonRequest '/jobs' 'POST' @{ action = 'apply'; sourceId = $stale.job.id; confirm = $true }
    do { Start-Sleep -Milliseconds 250; $failedDetail = JsonRequest "/jobs/$($failed.id)" } while ($failedDetail.job.status -in 'queued','running')
    Assert ($failedDetail.job.status -eq 'failed') 'Changed content invalidates a saved move preview'
    $emptyCleanup = Job 'cleanup-preview'
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'plan'; sourceId = $emptyCleanup.job.id } }
    [void](Job 'inventory')
    $companion = Join-Path $library 'Fixture.srm'
    [IO.File]::WriteAllBytes($original, $fixture)
    [IO.File]::WriteAllBytes($companion, [byte[]]@(1,2,3))
    $groupScan = Job 'scan'
    $groupPlan = Job 'plan' @{ sourceId = $groupScan.job.id; reviews = @(@{ path = $original; decision = 'original' }) }
    $groupResults = JsonRequest "/jobs/$($groupPlan.job.id)/results"
    Assert ($groupResults.total -eq 2) 'Companion files survive snapshot serialization'
    Assert (@($groupResults.items | Where-Object { $_.Target }).Count -eq 2) 'Companion relationships survive preview reload'
    [void](Job 'apply' @{ sourceId = $groupPlan.job.id; confirm = $true })
    $groupHistory = Job 'history'
    $groupJournals = @(JsonRequest "/jobs/$($groupHistory.job.id)/artifacts/history.json")
    [void](Job 'undo' @{ journal = $groupJournals[0].Name; confirm = $true })
    Assert ([IO.File]::Exists($original) -and [IO.File]::Exists($companion)) 'Companion unit can be moved and restored together'
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $archive = Join-Path $library 'Archive.zip'
    $zip = [IO.Compression.ZipFile]::Open($archive, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $zip.CreateEntry('Archive fixture.nes')
        $stream = $entry.Open()
        try { $stream.Write($fixture, 0, $fixture.Length) } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
    [void](Job 'workflow' @{ confirm = $true })
    Assert ([IO.File]::Exists((Join-Path $library 'Archive fixture.nes'))) 'Unpack-and-check extracts the synthetic archive'
    $archiveCleanup = Job 'cleanup-preview'
    $candidates = @(JsonRequest "/jobs/$($archiveCleanup.job.id)/artifacts/cleanup.json")
    Assert (@($candidates | Where-Object Eligible).Count -eq 1) "Archive cleanup requires surviving-copy evidence: $(ConvertTo-Json -InputObject $candidates -Depth 5)"
    $processedArchive = ($candidates | Where-Object Eligible | Select-Object -First 1).Path
    [void](Job 'cleanup' @{ sourceId = $archiveCleanup.job.id; confirm = $true })
    Assert (-not [IO.File]::Exists($processedArchive)) 'Approved cleanup removes only the processed recovery archive'
    Assert ([IO.File]::Exists((Join-Path $library 'Archive fixture.nes'))) 'Cleanup preserves the extracted ROM'
    $unpack = Job 'unpack' @{ confirm = $true }
    Assert ($unpack.job.status -in 'completed','completed-with-warnings') 'Standalone archive feature is independently dispatchable'
    $savedJobCount = @(JsonRequest '/jobs').Count
    [void](JsonRequest '/logout' 'POST')
    ExpectStatus 401 { Request '/jobs' }
    Stop-Process -Id $server.Id; $server.WaitForExit()
    $env:ROMCHECKER_TRUSTED_PROXIES = '127.0.0.1'
    $server = Start-Process -FilePath $Dotnet -ArgumentList "`"$((Resolve-Path $ServerDll).Path)`"" -PassThru -RedirectStandardOutput (Join-Path $root 'server-restarted.log') -RedirectStandardError (Join-Path $root 'server-restarted-error.log')
    for ($i = 0; $i -lt 60; $i++) {
        try { [void](Invoke-WebRequest "$base/healthz" -UseBasicParsing -TimeoutSec 2); break }
        catch { Start-Sleep -Milliseconds 250 }
    }
    $login = Request '/login' 'POST' @{ password = $env:ROMCHECKER_PASSWORD } @{ 'X-RomChecker' = '1'; 'X-Forwarded-Proto' = 'https'; Origin = "https://127.0.0.1:$port" }
    Assert (($login.Headers['Set-Cookie'] -join ';') -match 'secure') 'Trusted HTTPS forwarding creates Secure cookies'
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    [void](JsonRequest '/login' 'POST' @{ password = $env:ROMCHECKER_PASSWORD })
    Assert (@(JsonRequest '/jobs').Count -eq $savedJobCount) 'Job history persists across server restarts'
    Assert ((JsonRequest '/settings').autoDat -eq $false) 'Settings persist across server restarts'
    for ($i = 0; $i -lt 3; $i++) { ExpectStatus 401 { Request '/login' 'POST' @{ password = 'incorrect' } } }
    ExpectStatus 429 { Request '/login' 'POST' @{ password = 'incorrect' } }
    Write-Host "PASS: $passed web API integration assertions"
} finally {
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id; $server.WaitForExit() }
    if ($root -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force }
}
