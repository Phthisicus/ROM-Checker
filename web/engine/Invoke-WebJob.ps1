[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$jobDir = Split-Path $RequestPath
function Write-WebJson($Value, [string]$Path) {
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 8 -Compress), (New-Object Text.UTF8Encoding $false))
}
function Write-AtomicWebJson($Value, [string]$Path) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Write-WebJson $Value $temporary
        for ($attempt = 0; ; $attempt++) {
            try {
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
                else { [IO.File]::Move($temporary, $Path) }
                return
            } catch [IO.IOException] {
                if ($attempt -ge 5) { throw }
                Start-Sleep -Milliseconds (20 * ($attempt + 1))
            }
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
$engine = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'RomSorter.ps1'
. $engine -DefinitionsOnly
$script:ScriptPath = $engine
$S = Get-DefaultSettings
$S.RootFolder = $request.Root
$S.CheckOnly = $false
foreach ($property in $request.Settings.PSObject.Properties) {
    if (-not $S.Contains($property.Name)) { throw "Unknown setting: $($property.Name)" }
    $S[$property.Name] = $property.Value
}
$S.Emulators = ConvertTo-Hashtable $S.Emulators
if ($S.Console -ne 'All' -and -not (Get-Con $S.Console)) { throw "Unknown console: $($S.Console)" }
if ($script:OnWindows) {
    if ($env:ROMSORTER_VIRUSTOTAL_KEY) { Set-VtKey $env:ROMSORTER_VIRUSTOTAL_KEY }
    if ($env:ROMSORTER_MALWAREBAZAAR_KEY) { Set-MbKey $env:ROMSORTER_MALWAREBAZAAR_KEY }
}
$script:AppDir = Join-Path $request.DataDirectory 'engine'
[void][IO.Directory]::CreateDirectory($script:AppDir)
$script:SettingsPath = Join-Path $script:AppDir 'settings.json'
$script:OnlineCachePath = Join-Path $script:AppDir 'online-cache.json'
$script:OldVtCachePath = Join-Path $script:AppDir 'virustotal-cache.json'
$script:OnlineCache = $null
$script:OnlineCacheSaveWarning = $false
$script:ServiceIssues = New-Object Collections.ArrayList
$script:ProgressSink = {
    param($event)
    Write-AtomicWebJson $event (Join-Path $jobDir 'progress.json')
}
function Assert-WebPath([string]$Path) {
    if (-not $Path -or -not (Test-ChildPath $Path $S.RootFolder)) { throw "Path outside library: $Path" }
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Symbolic links and junctions are not allowed: $current"
        }
        if (Test-SamePath $current $S.RootFolder) { return }
        $current = Split-Path $current
    }
    throw "Cannot validate library path: $Path"
}
function Assert-WebResults($Items) {
    foreach ($item in $Items) {
        Assert-WebPath $item.FullName
        if ($item.Target) { Assert-WebPath $item.Target }
    }
}
function Assert-WebInternalTree([string]$Path) {
    $pending = New-Object Collections.Queue
    if (Test-Path -LiteralPath $Path) { $pending.Enqueue($Path) }
    while ($pending.Count) {
        $directory = [string]$pending.Dequeue()
        Assert-WebPath $directory
        foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Link in engine storage: $($entry.FullName)" }
            if ($entry.PSIsContainer) { $pending.Enqueue($entry.FullName) }
        }
    }
}
try {
    foreach ($reserved in '_RomSorter','_Unpacked archives','_Quarantine','_Duplicates','_Not valid') {
        Assert-WebPath (Join-Path $S.RootFolder $reserved)
    }
    Assert-WebInternalTree (Get-WorkDir)
    Assert-WebInternalTree (Join-Path $S.RootFolder $S.UnpackedFolder)
    if ($S.DatFolder) { Assert-WebPath $S.DatFolder }
    $results = @(); $cleanup = @(); $history = @()
    if ($request.SourceDirectory) {
        $snapshot = Import-Clixml -LiteralPath (Join-Path $request.SourceDirectory 'snapshot.xml')
        $results = @($snapshot | ForEach-Object { $_ })
        Assert-WebResults $results
    }
    $feature = $request.Feature
    if ($feature -cnotin 'Verification','Organization','Archives','Recovery','Workflows','Collections') {
        throw "Unsupported feature: $feature"
    }
    if ($request.Action -in 'apply','unpack','undo','cleanup','workflow') {
        $collectionIndex = Join-Path (Get-WorkDir) 'collection.json'
        if (Test-Path -LiteralPath $collectionIndex) { Remove-Item -LiteralPath $collectionIndex }
    }
    . (Join-Path (Join-Path $PSScriptRoot 'Features') "$feature.ps1")
    if ($results.Count) {
        Assert-WebResults $results
        $operationSummary = $script:LastProgressSummary
        $report = Export-Report $results 'Web'
        Copy-Item -LiteralPath $report -Destination (Join-Path $jobDir 'report.html')
        Copy-Item -LiteralPath (Join-Path (Get-WorkDir) 'Web-latest.csv') -Destination (Join-Path $jobDir 'report.csv')
        $script:LastProgressSummary = $operationSummary
    }
    Export-Clixml -InputObject $results -LiteralPath (Join-Path $jobDir 'snapshot.xml') -Depth 40
    $fields = 'FileName','FullName','Folder','Console','Category','Reason','Threats','Notes','Authenticity','IntegrityStatus','AntivirusStatus','MalwareStatus','DatStrength','Security','Sources','Libraries','Year','Publisher','Header','SHA256','SHA1','MD5','CRC32','Length','Target','Action','DupOf','SetId','CheckedUtc','AntivirusCheckedUtc','DatMatch','HashMatch','IdentificationStatus','IdentificationReason','CollectionId','Organization','HoldReason','Explanation'
    $publicResults = @($results | ForEach-Object {
        $item = $_ | Select-Object $fields
        $item | Add-Member NoteProperty Reviewable (-not $_.Lead -and $_.Category -ne 'Protected')
        $item
    })
    Write-WebJson $publicResults (Join-Path $jobDir 'results.json')
    Write-WebJson $cleanup (Join-Path $jobDir 'cleanup.json')
    Write-WebJson $history (Join-Path $jobDir 'history.json')
    $warnings = if ($script:ScanErrors) { $script:ScanErrors.Count } else { 0 }
    $counters = if ($script:LastProgressSummary) { $script:LastProgressSummary.Counters } else { @{} }
    $warnings += [int]$counters['Warnings'] + $script:ServiceIssues.Count
    $summary = [pscustomobject]@{ Count = $results.Count; Planned = @($results | Where-Object { $_.Target -and $_.Action -ne 'Moved' }).Count
        Warnings = $warnings; Counters = $counters; ServiceIssues = @($script:ServiceIssues) }
    Write-WebJson $summary (Join-Path $jobDir 'summary.json')
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    exit 1
}
