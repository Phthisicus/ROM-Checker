param(
    [string]$Dotnet = 'dotnet',
    [string]$PowerShell = 'pwsh',
    [string]$ServerDll = (Join-Path $PSScriptRoot '..\server\bin\Debug\net10.0\RomChecker.Web.dll'),
    [string]$SmbServer = ''
)
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('romchecker-storage-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$storage = $null; $server = $null; $passed = 0
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
function Port {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $listener.Start(); $value = $listener.LocalEndpoint.Port; $listener.Stop(); return $value
}
function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw "FAILED: $message" }; $script:passed++
}
function Request([string]$path, [string]$method = 'GET', $body = $null) {
    $parameters = @{ Uri = "$base/api$path"; Method = $method; WebSession = $session; UseBasicParsing = $true; Headers = @{ 'X-RomChecker' = '1' } }
    if ($null -ne $body) { $parameters.ContentType = 'application/json'; $parameters.Body = ConvertTo-Json -InputObject $body -Depth 12 }
    Invoke-WebRequest @parameters
}
function JsonRequest([string]$path, [string]$method = 'GET', $body = $null) {
    $response = Request $path $method $body
    if ($response.Content) { $response.Content | ConvertFrom-Json }
}
function ExpectStatus([int]$status, [scriptblock]$work) {
    $actual = 0
    try { $response = & $work; $actual = [int]$response.StatusCode }
    catch { if ($_.Exception.Response) { $actual = [int]$_.Exception.Response.StatusCode } else { throw } }
    Assert ($actual -eq $status) "HTTP $status (actual $actual)"
}
function Ready([string]$address, $process) {
    for ($i = 0; $i -lt 100; $i++) {
        if ($process.HasExited) { throw "Server exited. Logs: $root" }
        try { [void](Invoke-WebRequest "$address/healthz" -UseBasicParsing -TimeoutSec 2); return }
        catch { Start-Sleep -Milliseconds 200 }
    }
    throw 'Server did not become healthy.'
}
function WaitBatch([string]$id) {
    $until = [DateTime]::UtcNow.AddSeconds(90)
    do {
        Start-Sleep -Milliseconds 150
        $batch = JsonRequest "/storage/batches/$id"
    } while ($batch.status -in 'preparing','importing','processing' -and [DateTime]::UtcNow -lt $until)
    Assert ($batch.status -ne 'failed') "Batch transfer succeeds: $($batch.error)"
    return $batch
}
function Job([string]$action, $extra) {
    $request = @{ action = $action }
    foreach ($key in $extra.Keys) { $request[$key] = $extra[$key] }
    $job = JsonRequest '/jobs' 'POST' $request
    $until = [DateTime]::UtcNow.AddSeconds(90)
    do { Start-Sleep -Milliseconds 150; $detail = JsonRequest "/jobs/$($job.id)" }
    while ($detail.job.status -in 'queued','running','cancelling' -and [DateTime]::UtcNow -lt $until)
    if ($detail.job.status -notin 'completed','completed-with-warnings') {
        throw "Job failed: $($detail.job.error)`n$((Request "/jobs/$($job.id)/log").Content)"
    }
    return $detail
}
function Chunk([string]$id, [string]$fileId, [long]$offset, [byte[]]$content) {
    Invoke-WebRequest "$base/api/storage/batches/$id/uploads/${fileId}?offset=$offset" -Method PUT -WebSession $session `
        -Headers @{ 'X-RomChecker' = '1' } -ContentType 'application/octet-stream' -Body $content -UseBasicParsing
}
try {
    $dll = (Resolve-Path $ServerDll).Path
    $storagePort = Port; $appPort = Port
    $storageBase = "http://127.0.0.1:$storagePort"
    $base = "http://127.0.0.1:$appPort/roms"
    $env:ROMCHECKER_STORAGE_ROOT = Join-Path $root 'storage'
    $env:ROMCHECKER_STORAGE_TOKEN = 'storage-fixture-only-token-not-for-deployment'
    $env:ROMCHECKER_STORAGE_MAX_BYTES = '10485760'
    $env:ROMCHECKER_STORAGE_MAX_FILES = '100'
    $env:ROMCHECKER_STORAGE_RESERVE_BYTES = '0'
    $env:ROMCHECKER_SMB_HOSTS = $SmbServer
    $env:ROMCHECKER_ROLE = 'storage'
    $env:ROMCHECKER_PATH_BASE = ''
    $env:ASPNETCORE_URLS = $storageBase
    $storage = Start-Process -FilePath $Dotnet -ArgumentList "`"$dll`"" -PassThru `
        -RedirectStandardOutput (Join-Path $root 'storage.log') -RedirectStandardError (Join-Path $root 'storage-errors.log')
    Ready $storageBase $storage
    $env:ROMCHECKER_ROLE = ''
    $env:ROMCHECKER_STORAGE_URL = $storageBase
    $env:ROMCHECKER_LIBRARY = Join-Path $root 'library'
    [void][IO.Directory]::CreateDirectory($env:ROMCHECKER_LIBRARY)
    $env:ROMCHECKER_DATA = Join-Path $root 'data'
    $env:ROMCHECKER_ENGINE = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $env:ROMCHECKER_POWERSHELL = $PowerShell
    $env:ROMCHECKER_PASSWORD = 'fixture-only-password-not-for-deployment'
    $env:ROMCHECKER_PATH_BASE = '/roms'
    $env:ROMCHECKER_TRUSTED_PROXIES = ''
    $env:ASPNETCORE_URLS = "http://127.0.0.1:$appPort"
    $server = Start-Process -FilePath $Dotnet -ArgumentList "`"$dll`"" -PassThru `
        -RedirectStandardOutput (Join-Path $root 'server.log') -RedirectStandardError (Join-Path $root 'server-errors.log')
    Ready $base $server
    ExpectStatus 401 { Invoke-WebRequest "$storageBase/internal/batches" -UseBasicParsing }
    ExpectStatus 401 { Request '/storage/batches' }
    [void](JsonRequest '/login' 'POST' @{ password = $env:ROMCHECKER_PASSWORD })
    Assert ((JsonRequest '/storage/config').enabled) 'Storage is advertised through authenticated subpath API'
    $batch = JsonRequest '/storage/batches' 'POST' @{ name = 'Folder transfer' }
    $id = $batch.id
    ExpectStatus 400 { Request "/storage/batches/$id/uploads" 'POST' @{ path = '../outside.nes'; size = 3; modified = 1 } }
    ExpectStatus 400 { Request "/storage/batches/$id/uploads" 'POST' @{ path = 'C:/outside.nes'; size = 3; modified = 1 } }
    ExpectStatus 413 { Request "/storage/batches/$id/uploads" 'POST' @{ path = 'too-big.nes'; size = 10485761; modified = 1 } }
    $fixture = New-Object byte[] 40976
    $fixture[0] = 0x4e; $fixture[1] = 0x45; $fixture[2] = 0x53; $fixture[3] = 0x1a; $fixture[4] = 2; $fixture[5] = 1
    $upload = JsonRequest "/storage/batches/$id/uploads" 'POST' @{ path = 'Games/Fixture.nes'; size = $fixture.Length; modified = 1 }
    ExpectStatus 409 { Chunk $id $upload.id 1 ([byte[]]@(1,2)) }
    $partial = (Chunk $id $upload.id 0 $fixture[0..1023]).Content | ConvertFrom-Json
    Assert ($partial.offset -eq 1024 -and -not $partial.complete) 'Chunks preserve durable offsets'
    ExpectStatus 409 { Request "/storage/batches/$id/prepare" 'POST' }
    Stop-Process -Id $storage.Id; $storage.WaitForExit()
    $env:ROMCHECKER_ROLE = 'storage'; $env:ASPNETCORE_URLS = $storageBase
    $storage = Start-Process -FilePath $Dotnet -ArgumentList "`"$dll`"" -PassThru `
        -RedirectStandardOutput (Join-Path $root 'storage.log') -RedirectStandardError (Join-Path $root 'storage-errors.log')
    Ready $storageBase $storage
    $env:ROMCHECKER_ROLE = ''; $env:ASPNETCORE_URLS = "http://127.0.0.1:$appPort"
    $resume = JsonRequest "/storage/batches/$id/uploads" 'POST' @{ path = 'Games/Fixture.nes'; size = $fixture.Length; modified = 1 }
    Assert ($resume.offset -eq 1024) 'Reselection resumes an incomplete file after storage restart'
    ExpectStatus 409 { Request "/storage/batches/$id/uploads" 'POST' @{ path = 'games/fixture.nes'; size = $fixture.Length; modified = 1 } }
    $complete = (Chunk $id $upload.id 1024 $fixture[1024..($fixture.Length - 1)]).Content | ConvertFrom-Json
    Assert $complete.complete 'Completed upload is atomically promoted'
    ExpectStatus 409 { Request "/storage/batches/$id/uploads" 'POST' @{ path = 'Games/Fixture.nes'; size = $fixture.Length; modified = 2 } }
    $empty = JsonRequest "/storage/batches/$id/uploads" 'POST' @{ path = 'Games/empty.txt'; size = 0; modified = 1 }
    $emptyDone = (Chunk $id $empty.id 0 ([byte[]]@())).Content | ConvertFrom-Json
    Assert $emptyDone.complete 'Zero-byte files complete without an infinite upload loop'
    [void](Request "/storage/batches/$id/prepare" 'POST')
    $prepared = WaitBatch $id
    Assert ($prepared.prepared -and $prepared.status -eq 'ready') 'Preparation creates an isolated processing workspace'
    $originalPath = Join-Path $env:ROMCHECKER_STORAGE_ROOT "batches\$id\originals\Games\Fixture.nes"
    $processedPath = Join-Path $env:ROMCHECKER_STORAGE_ROOT "batches\$id\processed\Games\Fixture.nes"
    Assert ([IO.File]::Exists($originalPath) -and [IO.File]::Exists($processedPath)) 'Original and working copies are physically separate'
    [void](Job 'detect' @{ batchId = $id })
    $collection = JsonRequest "/collections/$id/files"
    Assert ($collection.total -eq 2 -and $collection.checkedFiles -eq 0) 'Detection groups files without claiming verification'
    $detectedRom = @($collection.items | Where-Object FileName -eq 'Fixture.nes')[0]
    Assert ($detectedRom.Console -eq 'NES') 'Local detection assigns the actual console'
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'verify'; batchId = $id; confirm = $true; selection = @('../outside') } }
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'verify'; batchId = $id; selection = @($detectedRom.CollectionId) } }
    ExpectStatus 409 { Request "/storage/batches/$id/uploads" 'POST' @{ path = 'later.nes'; size = 1; modified = 1 } }
    $settings = JsonRequest '/settings'
    $settings.defenderScan = $false; $settings.autoDat = $false; $settings.hasheous = 'Off'
    $settings.onlineCheck = 'Off'; $settings.identifyUnknown = $false; $settings.retailOnly = $false
    $scan = Job 'scan' @{ batchId = $id; settings = $settings }
    $results = JsonRequest "/jobs/$($scan.job.id)/results"
    Assert ($results.total -eq 2) 'Batch scan sees only that batch'
    Assert (@($results.items | Where-Object AntivirusStatus -eq 'Disabled').Count -gt 0) 'Per-job feature selection reaches the real engine'
    Assert ((JsonRequest '/settings').defenderScan) 'Per-job choices do not change global settings'
    $collectionSettings = $settings | Select-Object *
    $collectionSettings.requireDatMatch = $false
    [void](Job 'verify' @{ batchId = $id; settings = $collectionSettings; selection = @($detectedRom.CollectionId); organize = $true; confirm = $true })
    $verifiedCollection = JsonRequest "/collections/$id/files"
    Assert ($verifiedCollection.checkedFiles -eq 1) 'Selective verification leaves unselected files unchecked'
    Assert (@($verifiedCollection.items | Where-Object { $_.FileName -eq 'empty.txt' -and -not $_.CheckedUtc }).Count -eq 1) 'Unselected evidence is not fabricated'
    $verifiedRom = @($verifiedCollection.items | Where-Object FileName -eq 'Fixture.nes')[0]
    Assert ($verifiedRom.CollectionId -eq $detectedRom.CollectionId) 'Collection file identity survives verification'
    Assert ($verifiedRom.Organization -eq 'Organized') "Eligible file automatically organizes: $($verifiedRom.HoldReason)"
    Assert ([IO.File]::Exists($originalPath)) 'Automatic collection organization retains original uploads'
    [void](Job 'detect' @{ batchId = $id })
    $rediscovered = JsonRequest "/collections/$id/files"
    Assert ($rediscovered.total -eq 2 -and $rediscovered.checkedFiles -eq 1) 'Rediscovery preserves evidence for unchanged organized files'
    $currentLocation = $verifiedRom.RelativePath
    [void](Job 'verify' @{ batchId = $id; settings = $collectionSettings; selection = @($detectedRom.CollectionId); organize = $false; confirm = $true })
    $checkedOnly = JsonRequest "/collections/$id/files"
    $checkedRom = @($checkedOnly.items | Where-Object FileName -eq 'Fixture.nes')[0]
    Assert ($checkedRom.Organization -eq 'Checked only' -and $checkedRom.RelativePath -eq $currentLocation) 'Check-only mode does not move ROM files'
    $unavailable = $collectionSettings | Select-Object *
    $unavailable.onlineCheck = 'All'
    $incomplete = Job 'verify' @{ batchId = $id; settings = $unavailable; selection = @($detectedRom.CollectionId); organize = $true; confirm = $true }
    $held = JsonRequest "/collections/$id/files?filter=attention"
    Assert ($held.filtered -eq 1 -and $held.items[0].Organization -eq 'Held for review') 'Enabled unavailable security checks block automatic organization'
    Assert ($incomplete.summary.ServiceIssues.Count -gt 0) 'Unavailable services are reported separately from ROM findings'
    [void](Job 'verify' @{ batchId = $id; settings = $collectionSettings; organize = $true; confirm = $true })
    $allChecked = JsonRequest "/collections/$id/files"
    Assert ($allChecked.checkedFiles -eq 2 -and $allChecked.attention -gt 0) 'Verify everything retains invalid or unknown files for review'
    [void](Request "/storage/batches/$id/rename" 'POST' @{ name = 'Renamed collection' })
    Assert ((JsonRequest "/storage/batches/$id").name -eq 'Renamed collection') 'Collection names can change without altering files'
    Assert ((JsonRequest "/storage/batches/$id/capacity").processingBytes -ge $fixture.Length) 'Storage accounting includes working copies and reports'
    # Continue exercising the legacy preview/apply flow against the now-current location.
    $processedPath = Join-Path $env:ROMCHECKER_STORAGE_ROOT ("batches\$id\processed\" + $verifiedRom.RelativePath.Replace('/', '\'))
    $scan = Job 'scan' @{ batchId = $id; settings = $settings }
    ExpectStatus 400 { Request '/jobs' 'POST' @{ action = 'plan'; sourceId = $scan.job.id } }
    $plan = Job 'plan' @{ batchId = $id; sourceId = $scan.job.id; reviews = @(@{ path = $processedPath; decision = 'original' }) }
    Assert (-not $plan.job.settings.defenderScan) 'Batch review preserves selected scan settings'
    [void](Job 'apply' @{ batchId = $id; sourceId = $plan.job.id; confirm = $true })
    [void](WaitBatch $id)
    Assert ([IO.File]::Exists($originalPath)) 'Apply never touches the original import'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($originalPath)) -eq [Convert]::ToBase64String($fixture)) 'Original bytes remain identical after processing and apply'
    Assert (@(Get-ChildItem -LiteralPath $env:ROMCHECKER_LIBRARY -File -Recurse).Count -eq 0) 'Batch operations never touch the mounted legacy library'
    $browse = JsonRequest "/storage/batches/$id/browse?tree=processed"
    Assert ($browse.entries.Count -gt 0) 'Processed files are browsable'
    ExpectStatus 400 { Request "/storage/batches/$id/browse?path=.." }
    $zipPath = Join-Path $root 'download.zip'
    Invoke-WebRequest "$base/api/storage/batches/$id/download" -WebSession $session -OutFile $zipPath -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $romEntry = @($zip.Entries | Where-Object FullName -like '*Fixture.nes')
        Assert ($romEntry.Count -eq 1) 'Folder download streams a valid ZIP with processed ROMs'
        $stream = $romEntry[0].Open()
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            Assert ([Convert]::ToBase64String($memory.ToArray()) -eq [Convert]::ToBase64String($fixture)) 'ZIP ROM bytes are identical to the imported source'
        } finally { $stream.Dispose(); $memory.Dispose() }
    }
    finally { $zip.Dispose() }
    $leaseHeaders = @{ Authorization = "Bearer $env:ROMCHECKER_STORAGE_TOKEN" }
    $lease = [guid]::NewGuid().ToString('N')
    [void](Invoke-WebRequest "$storageBase/internal/batches/$id/lease" -Method POST -ContentType 'application/json' `
        -Body "{`"jobId`":`"$lease`"}" -Headers $leaseHeaders -UseBasicParsing)
    ExpectStatus 409 { Request "/storage/batches/$id" 'DELETE' }
    ExpectStatus 409 { Request "/storage/batches/$id/download" }
    ExpectStatus 409 { Request "/storage/batches/$id/browse" }
    Stop-Process -Id $server.Id; $server.WaitForExit()
    $server = Start-Process -FilePath $Dotnet -ArgumentList "`"$dll`"" -PassThru `
        -RedirectStandardOutput (Join-Path $root 'server.log') -RedirectStandardError (Join-Path $root 'server-errors.log')
    Ready $base $server
    Assert ((JsonRequest "/storage/batches/$id").status -eq 'ready') 'App restart recovers orphaned processing leases'
    $linkedBatch = JsonRequest '/storage/batches' 'POST' @{ name = 'Linked set fixture' }
    $linkedFiles = @(
        @{ path = 'Disc/Game.cue'; data = [Text.Encoding]::ASCII.GetBytes("FILE `"Track.bin`" BINARY`n  TRACK 01 MODE1/2352`n    INDEX 01 00:00:00`n") },
        @{ path = 'Disc/Track.bin'; data = (New-Object byte[] 2352) },
        @{ path = 'Other/Fixture.sms'; data = (New-Object byte[] 32768) }
    )
    foreach ($entry in $linkedFiles) {
        $registration = JsonRequest "/storage/batches/$($linkedBatch.id)/uploads" 'POST' @{ path = $entry.path; size = $entry.data.Length; modified = 1 }
        [void](Chunk $linkedBatch.id $registration.id 0 $entry.data)
    }
    [void](Request "/storage/batches/$($linkedBatch.id)/prepare" 'POST')
    [void](WaitBatch $linkedBatch.id)
    [void](Job 'detect' @{ batchId = $linkedBatch.id })
    $linked = JsonRequest "/collections/$($linkedBatch.id)/files"
    $track = @($linked.items | Where-Object FileName -eq 'Track.bin')[0]
    $descriptor = @($linked.items | Where-Object FileName -eq 'Game.cue')[0]
    Assert ($track.GroupId -eq $descriptor.GroupId) 'Detection keeps disc descriptors and tracks in the same selection unit'
    Assert (@($linked.groups | Where-Object key -eq 'SMS').Count -eq 1) 'A mixed collection groups a second console independently'
    [void](Job 'verify' @{ batchId = $linkedBatch.id; settings = $collectionSettings; selection = @($track.CollectionId); organize = $true; confirm = $true })
    $linkedResult = JsonRequest "/collections/$($linkedBatch.id)/files"
    Assert ($linkedResult.checkedFiles -eq 2) 'Selecting one track verifies the complete linked set, not unrelated consoles'
    Assert ($linkedResult.organized -eq 0) 'Unresolved or invalid disc sets are held intact instead of split or moved'
    [void](Request "/storage/batches/$($linkedBatch.id)" 'DELETE')
    $largeBatch = JsonRequest '/storage/batches' 'POST' @{ name = 'Large chunk fixture' }
    $large = JsonRequest "/storage/batches/$($largeBatch.id)/uploads" 'POST' @{ path = 'large.bin'; size = 8388611; modified = 1 }
    $largeData = New-Object byte[] 8388608
    $first = (Chunk $largeBatch.id $large.id 0 $largeData).Content | ConvertFrom-Json
    Assert ($first.offset -eq 8388608 -and -not $first.complete) 'An exact 8 MiB chunk streams through the proxy'
    $last = (Chunk $largeBatch.id $large.id 8388608 ([byte[]]@(1,2,3))).Content | ConvertFrom-Json
    Assert $last.complete 'Files larger than the request limit complete across multiple chunks'
    [void](JsonRequest "/storage/batches/$($largeBatch.id)/uploads" 'POST' @{ path = 'at-limit.bin'; size = 2097149; modified = 1 })
    ExpectStatus 413 { Request "/storage/batches/$($largeBatch.id)/uploads" 'POST' @{ path = 'over-limit.bin'; size = 1; modified = 1 } }
    [void](Request "/storage/batches/$($largeBatch.id)" 'DELETE')
    $limitBatch = JsonRequest '/storage/batches' 'POST' @{ name = 'File limit fixture' }
    for ($i = 0; $i -lt 100; $i++) {
        [void](JsonRequest "/storage/batches/$($limitBatch.id)/uploads" 'POST' @{ path = "file-$i.nes"; size = 0; modified = 1 })
    }
    ExpectStatus 413 { Request "/storage/batches/$($limitBatch.id)/uploads" 'POST' @{ path = 'one-too-many.nes'; size = 0; modified = 1 } }
    [void](Request "/storage/batches/$($limitBatch.id)" 'DELETE')
    ExpectStatus 403 { Request '/storage/smb' 'POST' @{ server = 'unapproved.invalid'; share = 'ROMs'; username = 'fixture'; password = 'fixture' } }
    if ($SmbServer) {
        $smb = JsonRequest '/storage/smb' 'POST' @{ server = $SmbServer; share = 'roms'; username = 'romfixture'; password = 'fixture-only-smb-password' }
        $remote = JsonRequest "/storage/smb/$($smb.id)/browse"
        Assert (@($remote.entries | Where-Object name -eq 'Fixture.nes').Count -eq 1) 'Real SMB share is browsable'
        Assert (@($remote.entries | Where-Object { $_.name -eq 'Games' -and $_.directory }).Count -eq 1) 'SMB folders can be selected for recursive import'
        $smbBatch = JsonRequest '/storage/batches' 'POST' @{ name = 'SMB fixture import' }
        [void](Request "/storage/batches/$($smbBatch.id)/smb-import" 'POST' @{ connectionId = $smb.id; paths = @('Fixture.nes','Games','Games/Nested/Fixture.nes') })
        $imported = WaitBatch $smbBatch.id
        Assert ($imported.files -eq 2 -and $imported.bytes -eq $fixture.Length * 2) 'Recursive SMB import deduplicates overlapping selections and copies bounded reads'
        $nested = JsonRequest "/storage/batches/$($smbBatch.id)/browse?tree=originals&path=Games%2FNested"
        Assert (@($nested.entries | Where-Object name -eq 'Fixture.nes').Count -eq 1) 'SMB import preserves nested paths'
        [void](Request "/storage/smb/$($smb.id)" 'DELETE')
        [void](Request "/storage/batches/$($smbBatch.id)" 'DELETE')
    }
    [void](Request "/storage/batches/$id" 'DELETE')
    ExpectStatus 404 { Request "/storage/batches/$id" }
    Assert (-not [IO.Directory]::Exists((Join-Path $env:ROMCHECKER_STORAGE_ROOT "batches\$id"))) 'Only explicit deletion removes original and processed storage'
    $interrupted = JsonRequest '/storage/batches' 'POST' @{ name = 'Interrupted SMB fixture' }
    $interruptedRoot = Join-Path $env:ROMCHECKER_STORAGE_ROOT "batches\$($interrupted.id)"
    [IO.File]::WriteAllBytes((Join-Path $interruptedRoot 'originals\completed.nes'), $fixture)
    $interrupted.status = 'importing'
    [IO.File]::WriteAllText((Join-Path $interruptedRoot 'batch.json'), (ConvertTo-Json -InputObject $interrupted -Depth 8))
    Stop-Process -Id $storage.Id; $storage.WaitForExit()
    $env:ROMCHECKER_ROLE = 'storage'; $env:ASPNETCORE_URLS = $storageBase
    $env:ROMCHECKER_STORAGE_RESERVE_BYTES = '9223372036854775807'
    $storage = Start-Process -FilePath $Dotnet -ArgumentList "`"$dll`"" -PassThru `
        -RedirectStandardOutput (Join-Path $root 'storage.log') -RedirectStandardError (Join-Path $root 'storage-errors.log')
    Ready $storageBase $storage
    $recoveredBatch = JsonRequest "/storage/batches/$($interrupted.id)"
    Assert ($recoveredBatch.status -eq 'failed' -and $recoveredBatch.files -eq 1 -and $recoveredBatch.bytes -eq $fixture.Length) 'Storage restart reconciles completed SMB copies before recording the interrupted transfer'
    [void](Request "/storage/batches/$($interrupted.id)" 'DELETE')
    $capacityBatch = JsonRequest '/storage/batches' 'POST' @{ name = 'Free space fixture' }
    ExpectStatus 507 { Request "/storage/batches/$($capacityBatch.id)/uploads" 'POST' @{ path = 'no-space.nes'; size = 1; modified = 1 } }
    Assert ((JsonRequest "/storage/batches/$($capacityBatch.id)").files -eq 0) 'Disk reserve failures never register success-shaped uploads'
    [void](Request "/storage/batches/$($capacityBatch.id)" 'DELETE')
    Write-Host "PASS: $passed storage integration assertions"
} catch {
    foreach ($log in 'storage.log','storage-errors.log','server.log','server-errors.log') {
        $path = Join-Path $root $log
        if (Test-Path -LiteralPath $path) { Write-Host "=== $log ==="; Get-Content -LiteralPath $path -Tail 30 | Write-Host }
    }
    throw
} finally {
    foreach ($process in @($server, $storage)) { if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id; $process.WaitForExit() } }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
