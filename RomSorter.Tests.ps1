<#
.SYNOPSIS
    Offline regression tests for Windows PowerShell 5.1 and PowerShell 7 on Ubuntu.
.DESCRIPTION
    Uses synthetic files in a unique temporary directory. Does not scan real ROMs,
    install packages, contact online services, or change the user's settings.
    Run with powershell -NoProfile -File .\RomSorter.Tests.ps1 or pwsh -File ./RomSorter.Tests.ps1.
#>
param([string]$Script = (Join-Path $PSScriptRoot 'RomSorter.ps1'))
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RomSorter-tests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$oldAppData = $env:APPDATA; $oldXdg = $env:XDG_CONFIG_HOME
$env:APPDATA = $testRoot; $env:XDG_CONFIG_HOME = $testRoot
$passed = 0
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:passed++
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    Assert ($null -ne $failure -and $failure.Exception.Message -match $Pattern) "$Message ($failure)"
}
function New-Fixture([string]$Relative, [byte[]]$Bytes) {
    $Relative = $Relative.Replace('\',[IO.Path]::DirectorySeparatorChar).Replace('/',[IO.Path]::DirectorySeparatorChar)
    $p = Join-Path $testRoot $Relative
    [void][IO.Directory]::CreateDirectory((Split-Path $p))
    [IO.File]::WriteAllBytes($p,$Bytes)
    Get-Item -LiteralPath $p
}
function New-TestZip([string]$Relative, [Collections.IDictionary]$Entries) {
    $file = New-Fixture $Relative @()
    $stream = [IO.File]::Open($file.FullName,[IO.FileMode]::Create)
    $zip = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries.Keys) {
            $entry = $zip.CreateEntry($name)
            $out = $entry.Open()
            try { $data = [byte[]]$Entries[$name]; $out.Write($data,0,$data.Length) } finally { $out.Dispose() }
        }
    } finally { $zip.Dispose(); $stream.Dispose() }
    Get-Item -LiteralPath $file.FullName
}
function Write-TestDat([string]$Name,[string]$System,[string]$Game,[byte[]]$Bytes,[string]$Extra = '') {
    $hashes = [RomSorter.RomTools]::HashBytes($Bytes,0,$Bytes.Length)
    $xml = "<datafile><header><name>$System</name></header><game name=`"$Game`"><rom name=`"fixture.rom`" size=`"$($Bytes.Length)`" crc=`"$($hashes[0])`" $Extra /></game></datafile>"
    [IO.File]::WriteAllText((Join-Path $datFolder "$Name.dat"),$xml)
}
try {
    $Script = (Resolve-Path -LiteralPath $Script).Path
    $source = [IO.File]::ReadAllText($Script)
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($Script,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Application parses'
    $prefix = [regex]::Split($source,'(?m)^# =+ START\s*$',2)[0]
    Assert ($prefix.Length -lt $source.Length) 'Load definitions without application entry point'
    . ([scriptblock]::Create($prefix))
    $script:ScriptPath = $Script
    $S = Get-DefaultSettings
    $S.RootFolder = Join-Path $testRoot 'library'
    [void][IO.Directory]::CreateDirectory($S.RootFolder)
    $S.DefenderScan = $false; $S.AutoDat = $false; $S.Hasheous = 'Off'
    $S.OnlineCheck = 'Off'; $S.CleanEmptyFolders = $false; $S.IdentifyUnknown = $false
    $datFolder = Join-Path $testRoot 'dats'; [void][IO.Directory]::CreateDirectory($datFolder)
    $S.DatFolder = $datFolder
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $nes = New-Object byte[] 40976
    $nes[0]=0x4e; $nes[1]=0x45; $nes[2]=0x53; $nes[3]=0x1a; $nes[4]=2; $nes[5]=1
    $file = New-Fixture 'library\NES\0001 Fixture (USA).nes' $nes
    $payload = New-Object byte[] 40960
    [Array]::Copy($nes,16,$payload,0,$payload.Length)
    $ph = [RomSorter.RomTools]::HashBytes($payload,0,$payload.Length)
    Write-TestDat 'nes' 'NES' 'Fixture (USA)' $payload "sha1=`"$($ph[2])`" sha256=`"$($ph[3])`""
    Write-TestDat 'snes' 'SNES' 'Other console (USA)' $payload
    Import-DatFolder @($datFolder)
    $r = Invoke-FileAnalysis $file $null
    Resolve-DatMatch $r
    Assert ($r.Console -eq 'NES') 'NES detected'
    Assert ($r.DatMatch -eq 'Fixture (USA)') 'Normalized payload matches system-scoped DAT'
    Assert ($r.DatStrength -eq 'SHA256') 'Strongest DAT hash is reported'
    Assert ($r.SHA256 -ne $ph[3]) 'Raw and normalized hashes are not confused'
    $r.Console = 'GBA'; Resolve-DatMatch $r
    Assert (-not $r.DatMatch) 'Cross-system CRC/size cannot match'
    $r.Console = 'NES'
    $key = "NES|$($payload.Length)|$($ph[0])"
    $script:DatIndex[$key][0].SHA256 = ('0' * 64)
    Resolve-DatMatch $r
    Assert (-not $r.DatMatch) 'Strong hash mismatch cannot fall back to CRC'
    $script:DatIndex[$key][0].SHA256 = ''
    $script:DatIndex[$key][0].SHA1 = ''
    Resolve-DatMatch $r
    Assert ($r.DatStrength -eq 'CRC32 + size') 'CRC-only DAT is explicitly labelled'
    $script:DatIndex[$key][0].SHA1 = $ph[2]
    Resolve-DatMatch $r
    Assert ($r.DatStrength -eq 'SHA1') 'SHA1 DAT is supported'
    $script:DatIndex[$key][0].SHA1 = ''
    $script:DatIndex[$key][0].MD5 = $ph[1]
    Resolve-DatMatch $r
    Assert ($r.DatStrength -eq 'MD5') 'MD5 DAT is supported'
    $script:DatIndex[$key][0].MD5 = ''
    [void]$script:DatIndex[$key].Add([pscustomobject]@{Name='Collision (USA)';SHA1='';SHA256='';MD5=''})
    Resolve-DatMatch $r
    Assert (-not $r.DatMatch) 'Ambiguous CRC-only releases are not selected arbitrarily'
    Import-DatFolder @($datFolder); Resolve-DatMatch $r
    $isolatedDat = Join-Path $testRoot 'isolated-dats'; [void][IO.Directory]::CreateDirectory($isolatedDat)
    [IO.File]::WriteAllText((Join-Path $isolatedDat 'mixed.dat'),"<datafile><header><name>Game Boy and Game Boy Color</name></header><game name=`"Wrong scope`"><rom size=`"$($payload.Length)`" crc=`"$($ph[0])`"/></game></datafile>")
    Import-DatFolder @($isolatedDat)
    Assert ($script:DatIndex.Count -eq 0) 'Ambiguous DAT system is not guessed'
    [IO.File]::WriteAllText((Join-Path $isolatedDat 'mixed.dat'),"clrmamepro (`n name NES`n)`ngame (`n name `"Text fixture (USA)`"`n rom ( name fixture.nes size $($payload.Length) crc $($ph[0]) sha1 $($ph[2]) )`n)")
    Import-DatFolder @($isolatedDat); Resolve-DatMatch $r
    Assert ($r.DatMatch -eq 'Text fixture (USA)' -and $r.DatStrength -eq 'SHA1') 'Text DAT preserves system scope and strong hashes'
    [IO.File]::WriteAllText((Join-Path $isolatedDat 'mixed.dat'),"<datafile><header><name>NES</name></header><game name=`"Strong only (USA)`"><rom size=`"$($payload.Length)`" sha256=`"$($ph[3])`"/></game></datafile>")
    Import-DatFolder @($isolatedDat); Resolve-DatMatch $r
    Assert ($r.DatMatch -eq 'Strong only (USA)' -and $r.DatStrength -eq 'SHA256') 'Strong-only DAT entries do not require CRC32'
    [IO.File]::WriteAllText((Join-Path $isolatedDat 'mixed.dat'),"<datafile><header><name>NES</name></header><game name=`"Malformed hash`"><rom size=`"$($payload.Length)`" crc=`"$($ph[0])`" sha256=`"bad`"/></game></datafile>")
    Import-DatFolder @($isolatedDat); Resolve-DatMatch $r
    Assert (-not $r.DatMatch) 'Malformed strong hashes cannot downgrade into weak verification'
    Import-DatFolder @($datFolder); Resolve-DatMatch $r
    $r.Category = Get-Verdict $r
    $r.AntivirusStatus = 'Disabled'; Update-EvidenceStatus @($r)
    Assert ($r.Authenticity -match '^Verified') 'Authenticity independent of AV'
    Assert ($r.MalwareStatus -eq 'Not fully checked') 'Disabled AV is not clean'
    $r.AntivirusStatus = 'Completed - no detections'; Update-EvidenceStatus @($r)
    Assert ($r.MalwareStatus -match 'not a safety guarantee') 'AV wording does not promise safety'
    $r.Header = 'Invalid'; Update-EvidenceStatus @($r)
    Assert ($r.IntegrityStatus -eq 'Failed checks' -and $r.Authenticity -match 'Verified') 'Conflicting integrity evidence remains visible'
    $r.Header = 'OK'
    Set-Security $r 'Suspicious' 'Synthetic warning'; Update-EvidenceStatus @($r)
    Assert ($r.MalwareStatus -eq 'Suspicious' -and $r.Authenticity -match 'Verified') 'Known dump does not suppress security findings'
    $r = Invoke-FileAnalysis $file $null
    $r.ScanFingerprint = Get-Sha256 $file.FullName
    $r.CheckedUtc = [DateTime]::UtcNow.ToString('o')
    $script:ScanContext = Get-ScanContext
    Write-ScanCheckpoint $r
    $restored = Read-ScanCheckpoint (Get-Item -LiteralPath $file.FullName)
    Assert ($restored.Resumed -and $restored.Cands.Count -gt 0) 'Per-file checkpoint survives interruption'
    Resolve-DatMatch $restored
    Assert ($restored.DatMatch -eq 'Fixture (USA)') 'Restored normalized strong hashes remain usable'
    $S.Strict = -not $S.Strict; $script:ScanContext = Get-ScanContext
    Assert ($null -eq (Read-ScanCheckpoint $file)) 'Settings changes invalidate cache'
    $S.Strict = -not $S.Strict; $script:ScanContext = Get-ScanContext
    $stamp = $file.LastWriteTimeUtc; $changed = [byte[]]$nes.Clone(); $changed[100] = 9
    [IO.File]::WriteAllBytes($file.FullName,$changed); [IO.File]::SetLastWriteTimeUtc($file.FullName,$stamp)
    Assert ($null -eq (Read-ScanCheckpoint (Get-Item -LiteralPath $file.FullName))) 'Same-size same-time content edits invalidate cache'
    [IO.File]::WriteAllBytes($file.FullName,$nes); [IO.File]::SetLastWriteTimeUtc($file.FullName,$stamp)
    [IO.File]::WriteAllText((Get-CheckpointPath $file.FullName),'broken cache')
    Assert ($null -eq (Read-ScanCheckpoint $file)) 'Corrupt checkpoint causes a fresh check'
    $S.ResumeScans = $false
    Assert ($null -eq (Read-ScanCheckpoint $file)) 'Fresh scan option disables reuse'
    $S.ResumeScans = $true
    $results = @(Invoke-Scan)
    Assert ($results.Count -eq 1) 'Real offline pipeline enumerates one ROM'
    Assert ($results[0].DatMatch -eq 'Fixture (USA)') 'Pipeline imports and matches scoped DAT'
    $results2 = @(Invoke-Scan)
    Assert ($results2[0].Resumed) 'Second pipeline run resumes local analysis'
    Assert ($results2[0].AntivirusStatus -eq 'Disabled') 'Cached analysis cannot invent an antivirus scan'
    $loaded = @(Restore-CompletedScan)
    Assert ($loaded.Count -eq 1 -and $loaded[0].ScanFingerprint) 'Completed check restores across sessions'
    $S.DefenderScan = $true
    $realAv = (Get-Item Function:Invoke-AntivirusScan).ScriptBlock; $script:avCalls = 0
    function Invoke-AntivirusScan($Path) { $script:avCalls++; @{ Available = $true; Hits = (New-PathMap); Message = 'Synthetic completed scan' } }
    try {
        $avFirst = @(Invoke-Scan); $avSecond = @(Invoke-Scan)
        Assert ($avSecond[0].Resumed -and $script:avCalls -eq 2) 'Antivirus runs again when local analysis resumes'
        Assert ($avSecond[0].AntivirusCheckedUtc -and $avSecond[0].AntivirusStatus -eq 'Completed - no detections') 'AV completion has an independent timestamp'
        function Invoke-AntivirusScan($Path) { @{ Available = $false; Hits = (New-PathMap); Message = 'Synthetic scan failure' } }
        $failedAv = @(Invoke-Scan)
        Assert ($failedAv[0].AntivirusStatus -eq 'Incomplete' -and $failedAv[0].MalwareStatus -notmatch '^No detections') 'Failed current AV cannot inherit prior clean status'
    } finally { Set-Item Function:Invoke-AntivirusScan $realAv; $S.DefenderScan = $false }
    $report = Export-Report $results2
    $reportText = [IO.File]::ReadAllText($report)
    foreach ($field in 'Authenticity:','Integrity:','Antivirus:','Malware:') { Assert ($reportText.Contains($field)) "HTML exposes $field" }
    $csv = Import-Csv -LiteralPath (Join-Path (Get-WorkDir) 'Preview-latest.csv')
    foreach ($field in 'Authenticity','IntegrityStatus','AntivirusStatus','MalwareStatus') { Assert ([bool]$csv.PSObject.Properties[$field]) "CSV exposes $field" }
    $sort = @(Get-SortInventory)
    Update-EvidenceStatus $sort
    Assert ($sort[0].Authenticity -eq 'Unverified' -and $sort[0].MalwareStatus -eq 'Not checked') 'Sort-only never claims verification'
    $copy = New-Fixture 'move-source.nes' $nes
    $dest = Join-Path $testRoot 'moved.nes'; $hash = Get-Sha256 $copy.FullName
    Assert-Throws { Move-OneFile $copy.FullName $dest ('0'*64) } 'changed' 'Move rejects stale expected hash'
    Assert ($copy.Exists -and -not [IO.File]::Exists($dest)) 'Rejected move preserves source'
    Move-OneFile $copy.FullName $dest $hash
    Assert ((Get-Sha256 $dest) -eq $hash) 'Moved bytes match source SHA256'
    $jr = New-JournalRow $r 'Moved' $copy.FullName $dest
    Assert ($jr.SHA256 -eq $hash) 'Journal records moved content hash'
    $log = Join-Path $testRoot 'undo.csv'; $jr | Export-Csv -LiteralPath $log -NoTypeInformation
    [IO.File]::WriteAllBytes($dest,$changed)
    Invoke-UndoLog (Get-Item -LiteralPath $log) $true
    Assert ([IO.File]::Exists($dest) -and [IO.File]::Exists($log)) 'Undo preserves edited moved file and recovery log'
    [IO.File]::WriteAllBytes($dest,$nes)
    Invoke-UndoLog (Get-Item -LiteralPath $log) $true
    Assert ([IO.File]::Exists($copy.FullName) -and -not [IO.File]::Exists($dest)) 'Undo restores unchanged moved file'
    $realSha = (Get-Item Function:Get-Sha256).ScriptBlock
    $script:tamperTarget = $dest; $script:tamperBytes = $changed
    function Get-Sha256([string]$Path) {
        if ($Path -eq $script:tamperTarget) { [IO.File]::WriteAllBytes($Path,$script:tamperBytes) }
        & $realSha $Path
    }
    try {
        Assert-Throws { Move-OneFile $copy.FullName $dest $hash } 'verification failed' 'Postmove checksum detects changed bytes'
        Assert ([IO.File]::Exists($copy.FullName) -and -not [IO.File]::Exists($dest)) 'Postmove failure restores the recoverable source path'
    } finally { Set-Item Function:Get-Sha256 $realSha; [IO.File]::WriteAllBytes($copy.FullName,$nes) }
    $extract = New-Fixture 'extract.nes' $nes
    $archive = New-TestZip 'archive.zip' @{ 'game.nes' = $nes }
    $jr = New-JournalRow $r 'Extracted' $archive.FullName $extract.FullName
    $jr | Export-Csv -LiteralPath $log -NoTypeInformation
    [IO.File]::WriteAllBytes($extract.FullName,$changed)
    Invoke-UndoLog (Get-Item -LiteralPath $log) $true
    Assert ([IO.File]::Exists($extract.FullName)) 'Undo preserves edited extracted file'
    [IO.File]::WriteAllBytes($extract.FullName,$nes)
    $originalArchive = [IO.File]::ReadAllBytes($archive.FullName)
    [IO.File]::WriteAllText($archive.FullName,'changed archive')
    Invoke-UndoLog (Get-Item -LiteralPath $log) $true
    Assert ([IO.File]::Exists($extract.FullName)) 'Undo preserves extract if original archive changed'
    [IO.File]::WriteAllBytes($archive.FullName,$originalArchive)
    $jr.SHA256 = ''; $jr | Export-Csv -LiteralPath $log -NoTypeInformation
    Invoke-UndoLog (Get-Item -LiteralPath $log) $true
    Assert ([IO.File]::Exists($extract.FullName)) 'Legacy extraction logs cannot delete unproven copies'
    $jr.SHA256 = Get-Sha256 $extract.FullName; $jr.Action = 'PlannedExtraction'
    $jr | Export-Csv -LiteralPath $log -NoTypeInformation
    Invoke-UndoLog (Get-Item -LiteralPath $log) $true
    Assert (-not [IO.File]::Exists($extract.FullName)) 'Write-ahead extraction entry recovers a crash before completion'
    $script:ArchiveBudget = $null
    $outFolder = Join-Path $testRoot 'expanded'
    Expand-ZipSafe $archive.FullName $outFolder
    Assert ((Get-Sha256 (Join-Path $outFolder 'game.nes')) -eq (Get-Sha256 $file.FullName)) 'ZIP extraction preserves bytes'
    Assert ($script:ArchiveBudget.Bytes -eq $nes.Length) 'Runtime byte budget counts actual output'
    $arcResult = New-Result $archive; [void](Test-Archive $arcResult $archive); Resolve-DatMatch $arcResult
    Assert (-not $arcResult.DatMatch) 'Archive CRC alone cannot satisfy strong member DAT'
    $slip = New-TestZip 'slip.zip' @{ '../outside.nes' = $nes }
    Assert-Throws { Expand-ZipSafe $slip.FullName (Join-Path $testRoot 'slip-output') } 'unsafe|zip-slip' 'ZIP traversal is blocked'
    Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot 'outside.nes'))) 'Traversal wrote nothing outside staging'
    $ads = New-TestZip 'streams.zip' @{ 'game.nes:payload' = $nes }
    Assert-Throws { Expand-ZipSafe $ads.FullName (Join-Path $testRoot 'streams-output') } 'unsafe path' 'Alternate stream paths are rejected'
    $big = New-TestZip 'big.zip' @{ 'large.nes' = (New-Object byte[] (2MB)) }
    $S.ArchiveMaxMB = 1; $script:ArchiveBudget = $null
    Assert-Throws { Expand-ZipSafe $big.FullName (Join-Path $testRoot 'limited') } 'byte limit' 'Streaming byte budget enforced'
    $limited = Get-Item -LiteralPath (Join-Path (Join-Path $testRoot 'limited') 'large.nes')
    Assert ($limited.Length -le 1MB) 'Disk output cannot exceed byte limit'
    $check = Test-ArchiveSafety $big '' ''
    Assert ($check.Skip -match 'byte limit' -and -not $check.Block) 'Resource limit is not a malware verdict'
    $S.ArchiveMaxMB = 16; $S.ArchiveMaxEntries = 1; $script:ArchiveBudget = $null
    $two = New-TestZip 'two.zip' @{ 'one.nes' = $nes; 'two.nes' = $nes }
    Assert-Throws { Expand-ZipSafe $two.FullName (Join-Path $testRoot 'two-out') } 'entry count' 'Entry count enforced at extraction'
    Assert-Throws { Get-ArchiveEntries $two } 'entry count' 'Entry count enforced at listing'
    $script:ArchiveBudget = $null
    Expand-ZipSafe $archive.FullName (Join-Path $testRoot 'first-budget')
    Assert-Throws { Expand-ZipSafe $archive.FullName (Join-Path $testRoot 'second-budget') } 'entry count' 'Entry budget is cumulative, not per archive'
    $S.ArchiveMaxEntries = 10000; $S.ArchiveTimeoutSeconds = 0
    Assert-Throws { Initialize-ArchiveBudget } 'Invalid archive setting' 'Invalid timeout cannot disable bounds'
    $S.ArchiveTimeoutSeconds = 300
    $native7z = (Get-Item Function:Get-SevenZip).ScriptBlock
    if (Get-SevenZip) {
        $script:ArchiveBudget = $null
        Expand-With7z $archive.FullName (Join-Path $testRoot '7zip-output')
        Assert ((Get-Sha256 (Join-Path (Join-Path $testRoot '7zip-output') 'game.nes')) -eq (Get-Sha256 $file.FullName)) 'External 7-Zip uses bounded streams'
    } else { Write-Host 'SKIP: real 7-Zip streaming test (7-Zip not installed)' }
    $script:testExecutable = (Get-Process -Id $PID).Path
    function Get-SevenZip { $script:testExecutable }
    $memory = New-Object IO.MemoryStream
    try {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        Assert-Throws { Invoke-Bounded7z @('-NoProfile','-Command','Start-Sleep -Seconds 10') $memory 1MB 500 } 'timeout' 'Hung child process is terminated'
        Assert ($timer.Elapsed.TotalSeconds -lt 5) 'Timeout does not wait for child completion'
        Assert-Throws { Invoke-Bounded7z @('-NoProfile','-Command',"[Console]::Out.Write(('x' * 10000))") $memory 64 5000 } 'byte limit' 'External extractor output limit is enforced'
    } finally { $memory.Dispose(); Set-Item Function:Get-SevenZip $native7z }
    $S.RootFolder = Join-Path $testRoot 'nested-library'
    [void][IO.Directory]::CreateDirectory($S.RootFolder)
    $inner = New-TestZip 'inner.zip' @{ 'deep.nes' = $nes }
    $outer = New-TestZip 'nested-library/outer.zip' @{ 'inner.zip' = [IO.File]::ReadAllBytes($inner.FullName) }
    $S.ArchiveMaxDepth = 0; $S.ArchiveMaxMB = 16; $script:UnpackBlocked = New-PathMap
    Invoke-Unpack
    Assert ((Test-Path -LiteralPath (Join-Path $S.RootFolder 'inner.zip')) -and -not (Test-Path -LiteralPath (Join-Path $S.RootFolder 'deep.nes'))) 'Nesting limit keeps deeper archives packed'
    $logs = @(Get-UndoLogs)
    Assert ($logs.Count -eq 1) 'Unpack writes one recovery journal'
    Invoke-UndoLog $logs[0] $true
    Assert ((Test-Path -LiteralPath $outer.FullName) -and -not (Test-Path -LiteralPath (Join-Path $S.RootFolder 'inner.zip'))) 'Unpack undo restores archive and removes unchanged copies'
    $S.ArchiveMaxDepth = 3
    Invoke-Unpack
    Assert (Test-Path -LiteralPath (Join-Path $S.RootFolder 'deep.nes')) 'Nested archive extraction works within depth budget'
    Assert (-not (Test-Path -LiteralPath (Join-Path $S.RootFolder 'inner.zip'))) 'Processed inner archives leave the active library'
    $nestedLogCount = @(Get-UndoLogs).Count
    Invoke-Unpack
    Assert (@(Get-UndoLogs).Count -eq $nestedLogCount) 'Rerunning unpack does not re-extract processed inner archives'
    $logs = @(Get-UndoLogs); Invoke-UndoLog $logs[0] $true
    Assert ((Test-Path -LiteralPath $outer.FullName) -and -not (Test-Path -LiteralPath (Join-Path $S.RootFolder 'deep.nes'))) 'Nested undo preserves recovery ordering'
    $S.RootFolder = Join-Path $testRoot 'incremental-library'
    $S.Layout = 'Validity'; $S.CheckOnly = $false
    $firstZip = New-TestZip 'incremental-library\downloads\batch\first.zip' @{ 'subfolder/First.nes' = $nes }
    Invoke-Unpack
    Assert (Test-Path -LiteralPath (Join-Path $firstZip.DirectoryName 'subfolder/First.nes')) 'ZIPs in subfolders extract their own subfolders'
    Assert (-not (Test-Path -LiteralPath $firstZip.FullName)) 'Processed ZIP is preserved outside the active tree'
    $firstRun = @(Invoke-Scan); Invoke-Organize $firstRun
    Assert ($firstRun.Count -eq 1 -and $firstRun[0].Action -eq 'Moved' -and (Test-Path -LiteralPath $firstRun[0].Target)) 'First run unpacks, checks and sorts a downloaded ROM'
    $stable = @(Invoke-Scan)
    Assert ($stable.Count -eq 1) 'Recovery archives are excluded from later ROM inventories'
    $later = New-Fixture 'incremental-library\incoming\Second.nes' $changed
    $laterZip = New-TestZip 'incremental-library\incoming\more\second.zip' @{ 'Third.nes' = $nes }
    Assert (-not (Test-CurrentInventory $stable)) 'Added ROM and ZIP invalidate existing inventory'
    Assert ($null -eq (Restore-CompletedScan)) 'Saved check cannot overlook newly added downloads'
    Assert (-not (Test-SortResults $stable)) 'Applying an old plan cannot silently skip new files'
    Invoke-Unpack
    $nextRun = @(Invoke-Scan)
    Assert ($nextRun.Count -eq 3) 'Later run includes existing ROM, new loose ROM and new extracted ROM'
    Assert (($nextRun | Where-Object FileName -eq 'First.nes').Resumed) 'Unchanged sorted ROM reuses its local check'
    Assert (-not ($nextRun | Where-Object FileName -eq 'Second.nes').Resumed -and -not ($nextRun | Where-Object FileName -eq 'Third.nes').Resumed) 'New ROMs receive fresh checks'
    Assert ($script:ScanChanges.New -eq 2 -and $script:ScanChanges.Reused -eq 1) 'Run summary distinguishes new files and reused checks'
    Invoke-Organize $nextRun
    Assert (@($nextRun | Where-Object { $_.FileName -in 'Second.nes','Third.nes' -and $_.Action -eq 'Moved' -and (Test-Path -LiteralPath $_.Target) }).Count -eq 2) 'New loose and zipped ROMs are both sorted without renaming'
    $beforeNoop = @(Get-UndoLogs).Count
    Invoke-Unpack
    Assert (@(Get-UndoLogs).Count -eq $beforeNoop) 'No new archives means no repeat extraction or empty undo log'
    $S.RootFolder = Join-Path $testRoot 'deep-library'
    $deep = $S.RootFolder
    foreach ($level in 1..70) { $deep = Join-Path $deep 'd' }
    [void][IO.Directory]::CreateDirectory((LongP $deep))
    [IO.File]::WriteAllBytes((LongP (Join-Path $deep 'Deep.nes')),$nes)
    $deepInventory = @(Get-ScanFiles)
    Assert ($deepInventory.Count -eq 1 -and $deepInventory[0].File.Name -eq 'Deep.nes') 'Discovery includes files deeper than 64 subfolders'
    $S.RootFolder = Join-Path $testRoot 'set-library'
    $track = New-Fixture 'set-library\PS1\Disc\track.bin' (New-Object byte[] 2048)
    $cue = New-Fixture 'set-library\PS1\Disc\game.cue' ([Text.Encoding]::ASCII.GetBytes("FILE `"track.bin`" BINARY`n  TRACK 01 MODE1/2048`n    INDEX 01 00:00:00`n"))
    $setResults = @(Invoke-Scan)
    $setLoaded = @(Restore-CompletedScan)
    $loadedCue = $setLoaded | Where-Object FileName -eq 'game.cue'
    $loadedTrack = $setLoaded | Where-Object FileName -eq 'track.bin'
    Assert ($loadedCue.SetMembers.Count -eq 1 -and [object]::ReferenceEquals($loadedTrack.Lead,$loadedCue)) 'Saved disc-set links are reconstructed without circular serialization'
    Assert ($loadedCue.Authenticity -eq 'Unverified') 'Complete disc set is not automatically authentic'
    $S.Layout = 'Validity'; Set-Targets $setLoaded
    Invoke-Organize $setLoaded
    $setLogs = @(Get-UndoLogs)
    Assert ($setLogs.Count -eq 1) 'Whole-set organization journals each move'
    $moveRows = @(Import-Csv -LiteralPath $setLogs[0].FullName)
    Assert (@($moveRows | Where-Object Action -eq 'PlannedMove').Count -eq 2) 'Whole-set moves have write-ahead recovery records'
    Invoke-UndoLog $setLogs[0] $true
    Assert ((Test-Path -LiteralPath $cue.FullName) -and (Test-Path -LiteralPath $track.FullName)) 'Disc set restores together'
    $S.RootFolder = Join-Path $testRoot 'bios-library'
    $biosCases = @(
        @('loose/scph5501.bin','PS1'), @('loose/SCPH-70004_BIOS_V12_PAL_200.BIN','PS2'),
        @('loose/gba_bios.bin','GBA'), @('loose/cgb_boot.bin','GBC'), @('loose/dmg_boot.bin','GB'),
        @('loose/bios7.bin','NDS'), @('loose/boot9.bin','3DS'), @('loose/dc_boot.bin','DC'),
        @('loose/sega_101.bin','SATURN'), @('loose/bios_CD_U.bin','SEGACD'),
        @('loose/disksys.rom','FDS'), @('loose/syscard3.pce','PCECD'),
        @('loose/kick34005.A500.rom','AMIGA'), @('PSP/incoming/firmware.bin','PSP'),
        @('loose/lynxboot.img','LYNX')
    )
    foreach ($case in $biosCases) {
        $fixture = New-Fixture ('bios-library/' + $case[0]) (New-Object byte[] 512)
        $identity = Get-BiosIdentity $fixture
        Assert ($identity.Console -eq $case[1]) "BIOS console identified: $($fixture.Name)"
    }
    $unknownFirmware = New-Fixture 'bios-library/unknown/firmware.bin' (New-Object byte[] 512)
    $keys = New-Fixture 'bios-library/SWITCH/prod.keys' ([Text.Encoding]::ASCII.GetBytes('synthetic test only'))
    $packedBios = New-TestZip 'bios-library/loose/neogeo.zip' @{ 'bios.rom' = (New-Object byte[] 512) }
    $biosExecutable = New-Fixture 'bios-library/loose/gba_bios.exe' ([byte[]]@(1,2,3))
    $installed = New-Fixture 'bios-library/emulator/scph5501.bin' (New-Object byte[] 512)
    [void](New-Fixture 'bios-library/emulator/retroarch.exe' ([byte[]]@(1,2,3)))
    $S.Layout = 'Validity'
    $biosInventory = @(Get-SortInventory)
    Set-Targets $biosInventory
    foreach ($case in $biosCases) {
        $casePath = Join-Path $S.RootFolder (Convert-RelativePath $case[0])
        $entry = $biosInventory | Where-Object FullName -eq $casePath
        $expected = Join-Path (Join-Path (Join-Path $S.RootFolder (Get-Con $case[1]).Folder) 'BIOS') $entry.FileName
        Assert ($entry.Category -eq 'BIOS' -and (Test-SamePath $entry.Target $expected)) "Sort-only plans console BIOS subfolder: $($entry.FileName)"
        Assert ($entry.Security -eq 'Not checked') 'BIOS sort-only performs no security scan'
    }
    Assert (-not ($biosInventory | Where-Object FullName -eq $unknownFirmware.FullName).Target) 'Ambiguous firmware stays in place'
    Assert (-not ($biosInventory | Where-Object FullName -eq $keys.FullName).Target) 'Key material stays in place'
    Assert (-not ($biosInventory | Where-Object FullName -eq $packedBios.FullName).Target) 'Arcade BIOS ZIP stays packed and in place'
    Assert (($biosInventory | Where-Object FullName -eq $installed.FullName).Category -eq 'Protected') 'Installed emulator BIOS is protected'
    $oldOnWindows = $script:OnWindows
    try {
        $script:OnWindows = $false
        $romDemo = New-Fixture 'linux-app-check/roms/SNES9X Demo V1.16 (PD).smc' (New-Object byte[] 512)
        Assert (-not (Test-AppFolder $romDemo.Directory @(Get-ChildItem -LiteralPath $romDemo.DirectoryName -Force))) 'Linux: ROM named after an emulator does not protect its folder'
        $linuxApp = New-Fixture 'linux-app-check/app/snes9x-gtk' ([byte[]]@(1,2,3))
        $mode = $linuxApp.PSObject.Properties['UnixFileMode']
        if ($mode -and [IO.Path]::DirectorySeparatorChar -ne '\') { $linuxApp.UnixFileMode = [IO.UnixFileMode]'UserRead, UserWrite, UserExecute' }
        Assert ([bool](Test-AppFolder $linuxApp.Directory @(Get-ChildItem -LiteralPath $linuxApp.DirectoryName -Force))) 'Linux: extensionless emulator program still protects its folder'
    } finally { $script:OnWindows = $oldOnWindows }
    Assert (-not ($biosInventory | Where-Object FullName -eq $biosExecutable.FullName).Target) 'BIOS-like executable is never treated as movable firmware'
    $biosScan = @(Invoke-Scan)
    $gbaBios = $biosScan | Where-Object FileName -eq 'gba_bios.bin'
    Assert ($gbaBios.Category -eq 'BIOS' -and $gbaBios.Authenticity -eq 'Unverified' -and $gbaBios.ScanFingerprint) 'Checked BIOS gets fingerprint without falsely claiming authenticity'
    $biosOriginalPaths = @($biosScan | Where-Object Target | ForEach-Object FullName)
    Invoke-Organize $biosScan
    Assert (Test-Path -LiteralPath (Join-Path (Join-Path $S.RootFolder 'GBA/BIOS') 'gba_bios.bin')) 'BIOS move preserves filename in console BIOS folder'
    $biosAfter = @(Get-SortInventory)
    Set-Targets $biosAfter
    Assert (-not @($biosAfter | Where-Object { $_.Category -eq 'BIOS' -and $_.Target }).Count) 'Already organised BIOS stays put on repeat runs'
    $biosLogs = @(Get-UndoLogs); Invoke-UndoLog $biosLogs[0] $true
    foreach ($original in $biosOriginalPaths) { Assert (Test-Path -LiteralPath $original) 'BIOS sorting is undoable with hash-safe journal' }
    $tagged = New-Fixture 'bios-library/tagged/[BIOS] Nintendo Game Boy Advance (World).gba' (New-Object byte[] 512)
    $taggedId = Get-BiosIdentity $tagged
    Assert ($taggedId.Console -eq 'GBA' -and $taggedId.Movable) 'Explicit BIOS tags can identify console without a parent hint'
    $S.Console = 'SNES'
    $filteredBios = Invoke-FileAnalysis $tagged $null
    Assert ($filteredBios.Category -eq 'Other_Console' -and -not $filteredBios.BiosMovable) 'Console filters apply to BIOS sorting'
    $S.Console = 'All'
    $dangerBiosZip = New-TestZip 'bios-library/suspicious/bios.zip' @{ 'setup.exe' = ([byte[]]@(1,2,3)) }
    $dangerBiosResult = Invoke-FileAnalysis $dangerBiosZip $null
    Assert ($dangerBiosResult.Security -in 'Suspicious','Malicious') 'BIOS archive labels do not bypass archive content security checks'
    $existingBios = New-Fixture 'bios-library/PS1/BIOS/scph5501.bin' ([byte[]]@(1,2,3,4))
    $clashInventory = @(Get-SortInventory); Set-Targets $clashInventory
    $clashing = $clashInventory | Where-Object { $_.FileName -eq 'scph5501.bin' -and $_.FullName -ne $existingBios.FullName -and $_.Category -eq 'BIOS' }
    Assert ($clashing.Target -and (Split-Path $clashing.Target -Leaf) -eq 'scph5501.bin' -and $clashing.Target -ne $existingBios.FullName) 'BIOS name collisions preserve both files without renaming'
    $S.RootFolder = Join-Path $testRoot 'cleanup-library'; $S.Layout = 'Validity'
    $cleanupInner = New-TestZip 'cleanup-inner.zip' @{ 'Clean.nes' = $nes }
    $cleanupOuter = New-TestZip 'cleanup-library/incoming/outer.zip' @{ 'inner.zip' = [IO.File]::ReadAllBytes($cleanupInner.FullName) }
    Invoke-Unpack
    $cleanupResults = @(Invoke-Scan); Invoke-Organize $cleanupResults
    $records = @(Get-CleanupRecords); $cleanupPlan = @(Get-ArchiveCleanupPlan $records)
    Assert ($cleanupPlan.Count -eq 2 -and @($cleanupPlan | Where-Object Eligible).Count -eq 2) 'Cleanup verifies outer and inner archive copies after ROM sorting'
    foreach ($item in $cleanupPlan) { Assert (Test-Path -LiteralPath $item.Path) 'Cleanup preview never deletes archives' }
    $cleanRom = $cleanupResults | Where-Object FileName -eq 'Clean.nes'
    $cleanTarget = $cleanRom.Target
    [IO.File]::WriteAllBytes($cleanTarget,$changed)
    $changedPlan = @(Get-ArchiveCleanupPlan $records)
    Assert (-not @($changedPlan | Where-Object Eligible).Count) 'Changed extracted ROM blocks cleanup of inner and outer archives'
    Invoke-ArchiveCleanup $cleanupPlan
    foreach ($item in $cleanupPlan) { Assert (Test-Path -LiteralPath $item.Path) 'Cleanup rechecks extracted copies after preview and preserves archives' }
    [IO.File]::WriteAllBytes($cleanTarget,$nes)
    $untracked = New-TestZip 'cleanup-library/_Unpacked archives/untracked.zip' @{ 'Untracked.nes' = $nes }
    $activeArcade = New-TestZip 'cleanup-library/MAME/parent.zip' @{ 'chip.rom' = (New-Object byte[] 512) }
    $cleanPlan = @(Get-ArchiveCleanupPlan @(Get-CleanupRecords))
    Assert ($cleanPlan.Count -eq 2) 'Untracked and arcade archives are never cleanup candidates'
    $outerCandidate = $cleanPlan | Where-Object { (Split-Path $_.Path -Leaf) -eq 'outer.zip' }
    $outerBytes = [IO.File]::ReadAllBytes($outerCandidate.Path)
    [IO.File]::WriteAllText($outerCandidate.Path,'changed archive')
    Assert (-not (Get-ArchiveCleanupPlan @(Get-CleanupRecords) | Where-Object Path -eq $outerCandidate.Path).Eligible) 'Changed archive is excluded from cleanup'
    [IO.File]::WriteAllBytes($outerCandidate.Path,$outerBytes)
    $noCompletion = @($records | Where-Object Action -ne 'ExtractionCompleted')
    Assert (-not @(Get-ArchiveCleanupPlan $noCompletion | Where-Object Eligible).Count) 'Incomplete or legacy extraction evidence cannot authorize deletion'
    $bannerCleanup = (Get-Item Function:Show-Banner).ScriptBlock
    $confirmCleanup = (Get-Item Function:Confirm-Action).ScriptBlock
    $waitCleanup = (Get-Item Function:Wait-Key).ScriptBlock
    function Show-Banner {}
    function Confirm-Action { $false }
    function Wait-Key {}
    try {
        Show-ArchiveCleanupMenu
        foreach ($item in $cleanPlan) { Assert (Test-Path -LiteralPath $item.Path) 'Cancelling cleanup preserves every archive' }
    } finally { Set-Item Function:Show-Banner $bannerCleanup; Set-Item Function:Confirm-Action $confirmCleanup; Set-Item Function:Wait-Key $waitCleanup }
    Invoke-ArchiveCleanup $cleanPlan
    foreach ($item in $cleanPlan) { Assert (-not (Test-Path -LiteralPath $item.Path)) 'Confirmed cleanup removes verified processed archive' }
    Assert ((Test-Path -LiteralPath $cleanTarget) -and (Get-Sha256 $cleanTarget) -eq (Get-Sha256 $file.FullName)) 'Cleanup leaves sorted ROM bytes intact'
    Assert ((Test-Path -LiteralPath $untracked.FullName) -and (Test-Path -LiteralPath $activeArcade.FullName)) 'Cleanup preserves untracked and arcade ZIP files'
    $cleanupReports = @(Get-ChildItem -LiteralPath (Get-WorkDir) -Filter 'Cleanup-*.csv')
    $deletions = @($cleanupReports | ForEach-Object { Import-Csv -LiteralPath $_.FullName } | Where-Object Action -eq 'Deleted')
    Assert ($deletions.Count -eq 2) 'Permanent archive deletion is recorded in cleanup audit CSV'
    Assert (-not @(Get-ArchiveCleanupPlan @(Get-CleanupRecords)).Count) 'Repeated cleanup does not reoffer deleted archives'
    $unpackLog = Get-UndoLogs | Where-Object Name -like '*unpack*' | Select-Object -First 1
    Invoke-UndoLog $unpackLog $true
    Assert (Test-Path -LiteralPath $cleanTarget) 'Undo after cleanup cannot delete surviving sorted ROM'
    $S.RootFolder = Join-Path $testRoot 'arcade-library'
    $arcade = New-TestZip 'arcade-library\MAME\parent.zip' @{ 'chip.rom' = (New-Object byte[] 2048) }
    $inventory = @(Get-SortInventory)
    Assert ($inventory.Count -eq 1 -and -not $inventory[0].Target) 'Arcade dependencies remain packed and protected in sort-only inventory'
    $realBanner = (Get-Item Function:Show-Banner).ScriptBlock
    $realChoice = (Get-Item Function:Read-Choice).ScriptBlock
    $realScan = (Get-Item Function:Invoke-Scan).ScriptBlock
    function Show-Banner {}
    function Read-Choice { 'B' }
    function Invoke-Scan { throw 'Sort menu must not initiate a scan' }
    try {
        $script:LastResults = $null
        Show-SortMenu 'Validity'
        Assert ($null -eq $script:LastResults -or $script:LastResults.Count -eq 0) 'Sort menu Back does not trigger checking or antivirus'
    } finally { Set-Item Function:Show-Banner $realBanner; Set-Item Function:Read-Choice $realChoice; Set-Item Function:Invoke-Scan $realScan }
    Assert ($script:Consoles.Count -ge 64) 'Existing system profiles remain available'
    $mapped = 0
    foreach ($systemEntry in $script:Consoles) { foreach ($extension in $systemEntry.Ext) { Assert ($script:ExtMap.ContainsKey($extension)) "Extension map includes $($systemEntry.Key) $extension"; $mapped++ } }
    Assert ($mapped -eq 149) "All 149 registered extension associations are exercised ($mapped entries)"
    Assert ((Get-DefaultSettings).IdentifyUnknown) 'Unknown-file hash identification defaults on'
    foreach ($case in @(@('Nintendo - Super Nintendo Entertainment System','SNES'),@('Super Famicom','SNES'),@('Nintendo Entertainment System','NES'),@('Sega Genesis','MD'),@('Sony PlayStation','PS1'),@('Sony PlayStation Portable','PSP'),@('Nintendo Game Boy Color','GBC'),@('Sega Naomi 2','NAOMI2'))) {
        Assert ((Get-OnlineConsole $case[0]).Key -eq $case[1]) "Exact online platform alias: $($case[0])"
    }
    Assert ($null -eq (Get-OnlineConsole 'Sony PlayStation 5')) 'Unsupported generations are never guessed from a substring'
    Assert ($null -eq (Get-OnlineConsole 'Nintendo DSi')) 'DSi is not guessed as Nintendo DS'
    $savedRoot = $S.RootFolder; $S.RootFolder = Join-Path $testRoot 'identification-library'
    [void][IO.Directory]::CreateDirectory($S.RootFolder)
    $realLookup = (Get-Item Function:Invoke-HasheousLookup).ScriptBlock
    $script:lookupCalls = 0; $script:lookupAnswer = $null
    function Invoke-HasheousLookup($Md5) { $script:lookupCalls++; $script:lookupAnswer }
    function New-IdentificationAnswer($Fixture,[string]$Name='Fixture game.bin',[string]$Platform='Sega Genesis') {
        $hashes = @(Get-RomHashes $Fixture.FullName)
        [pscustomobject]@{ Status='Found'; Name=$Name; Game=$Name; Platform=$Platform; System=$Platform; GameCategory=''
            Source='NoIntros'; MD5=$hashes[1]; SHA1=$hashes[2]; SHA256=$hashes[3]; Length=$Fixture.Length; Date=(Get-Date).ToString('s') }
    }
    try {
        $S.IdentifyUnknown = $true; $S.Hasheous = 'Off'; $script:CancelOnline = $false
        $unknownFile = New-Fixture 'identification-library/mystery.blob' ([byte[]]@(1,3,5,7,9,11))
        $script:lookupAnswer = New-IdentificationAnswer $unknownFile
        $identified = Invoke-FileAnalysis $unknownFile $null
        Assert ($identified.Console -eq '-') 'Unknown file begins without console guess'
        $identificationOutput = @(Invoke-UnknownIdentification @($identified))
        Assert ($identificationOutput.Count -eq 0 -and $identified.IdentificationStatus -eq 'Identified' -and $identified.Console -eq 'MD') 'Strong online hash assigns console without polluting output'
        Assert ($identified.HashMatch -and $identified.FileName -eq 'mystery.blob' -and $identified.Security -eq 'Clean') 'Online identification keeps filename and independent security evidence'
        $before = $script:lookupCalls
        $identifiedAgain = Invoke-FileAnalysis $unknownFile $null
        Invoke-UnknownIdentification @($identifiedAgain)
        Assert ($script:lookupCalls -eq $before -and $identifiedAgain.Console -eq 'MD') 'Successful hash lookup persists and avoids repeat requests'
        $script:OnlineCache = $null
        $afterReload = Invoke-FileAnalysis $unknownFile $null
        Invoke-UnknownIdentification @($afterReload)
        Assert ($script:lookupCalls -eq $before -and $afterReload.Console -eq 'MD') 'Successful identity cache survives a fresh process/cache reload'
        $biosFile = New-Fixture 'identification-library/firmware.bin' ([byte[]]@(2,4,6,8,10,12))
        $script:lookupAnswer = New-IdentificationAnswer $biosFile '[BIOS] PlayStation firmware.bin' 'Sony PlayStation'
        $onlineBios = Invoke-FileAnalysis $biosFile $null
        Invoke-UnknownIdentification @($onlineBios)
        Set-Targets @($onlineBios)
        Assert ($onlineBios.IdentificationStatus -eq 'Identified' -and $onlineBios.Category -eq 'BIOS' -and $onlineBios.Console -eq 'PS1') 'Unknown firmware is identified through reference hash'
        Assert ($onlineBios.BiosMovable -and $onlineBios.Target -eq (Join-Path (Join-Path (Join-Path $S.RootFolder 'PS1') 'BIOS') 'firmware.bin')) 'Online firmware uses console BIOS subfolder without renaming'
        foreach ($mode in 'Weak','Mismatch','Wrong size','Missing size','Conflicting systems','Unsupported') {
            $script:OnlineCache = @{}
            $script:lookupAnswer = New-IdentificationAnswer $unknownFile
            switch ($mode) {
                'Weak' { $script:lookupAnswer.SHA1=''; $script:lookupAnswer.SHA256='' }
                'Mismatch' { $script:lookupAnswer.SHA256='0'*64 }
                'Wrong size' { $script:lookupAnswer.Length=999 }
                'Missing size' { $script:lookupAnswer.Length=$null }
                'Conflicting systems' { $script:lookupAnswer.System='Sony PlayStation' }
                'Unsupported' { $script:lookupAnswer.Platform='Unsupported Box'; $script:lookupAnswer.System='Unsupported Box' }
            }
            $clue = Invoke-FileAnalysis $unknownFile $null
            Invoke-UnknownIdentification @($clue)
            Assert ($clue.Console -eq '-' -and -not $clue.HashMatch -and $clue.OnlineName) "Uncertain reference never becomes automatic identity: $mode"
            Assert ($clue.IdentificationStatus -in 'Needs review','Unsupported platform') "Uncertain reference reason is reported: $mode"
            if ($mode -eq 'Weak') {
                $before=$script:lookupCalls
                Invoke-UnknownIdentification @((Invoke-FileAnalysis $unknownFile $null))
                Assert ($script:lookupCalls -eq $before+1) 'Weak/malformed references retry later instead of being cached as completed'
            }
        }
        $script:OnlineCache = @{}; $script:lookupAnswer = [pscustomobject]@{ Status='Unknown'; Date=(Get-Date).ToString('s') }
        $before = $script:lookupCalls
        $miss = Invoke-FileAnalysis $unknownFile $null; $duplicateMiss = Invoke-FileAnalysis $unknownFile $null
        Invoke-UnknownIdentification @($miss,$duplicateMiss)
        Assert ($script:lookupCalls -eq $before+1 -and $miss.IdentificationStatus -eq 'Unknown') 'Unknown hashes are deduplicated within the run'
        Invoke-UnknownIdentification @((Invoke-FileAnalysis $unknownFile $null))
        Assert ($script:lookupCalls -eq $before+2) 'Unknown hashes are retried on the next run, not cached as completed'
        foreach ($state in 'Quota','Error') {
            $script:OnlineCache=@{}; $script:lookupAnswer=[pscustomobject]@{ Status=$state; Message='Synthetic service unavailable' }
            $first = Invoke-FileAnalysis $unknownFile $null; $second = Invoke-FileAnalysis $biosFile $null
            $before=$script:lookupCalls
            Invoke-UnknownIdentification @($first,$second)
            Assert ($script:lookupCalls -eq $before+1 -and $first.IdentificationStatus -eq $state -and $second.IdentificationStatus -eq 'Deferred') "Service failure stops requests and leaves truthful retry state: $state"
        }
        $script:OnlineCache=@{}; $script:lookupAnswer=New-IdentificationAnswer $unknownFile
        $script:IdentificationStop=''
        $knownUnmatched = Invoke-FileAnalysis $file $null
        $script:lookupAnswer=[pscustomobject]@{ Status='Unknown'; Date=(Get-Date).ToString('s') }
        Invoke-HasheousCheck @($knownUnmatched)
        Assert ($knownUnmatched.IdentificationStatus -eq 'Unknown') 'Unmatched known-console ROM is reported even with normal online verification off'
        $knownRetry = Invoke-FileAnalysis $file $null; $before=$script:lookupCalls
        Invoke-HasheousCheck @($knownRetry)
        Assert ($script:lookupCalls -eq $before+1) 'Previously unknown known-console ROM hash is retried'
        $script:OnlineCache=@{}; $script:lookupAnswer=New-IdentificationAnswer $unknownFile
        $S.IdentifyUnknown=$false; $disabled=Invoke-FileAnalysis $unknownFile $null; $before=$script:lookupCalls
        Invoke-UnknownIdentification @($disabled)
        Assert ($disabled.IdentificationStatus -eq 'Disabled' -and $script:lookupCalls -eq $before) 'Opt-out never submits unknown hashes'
        $S.IdentifyUnknown=$true; $limit=$S.HashLimitMB; $S.HashLimitMB=0
        $limited=Invoke-FileAnalysis $unknownFile $null; Invoke-UnknownIdentification @($limited); $S.HashLimitMB=$limit
        Assert ($limited.IdentificationStatus -eq 'Hash limit' -and $script:lookupCalls -eq $before) 'Unknown identification respects hash size budget'
        $protected=Invoke-FileAnalysis $unknownFile $null; $protected.Category='Protected'
        $keys=Invoke-FileAnalysis (New-Fixture 'identification-library/prod.keys' ([byte[]]@(1,2,3))) $null
        $unsafe=Invoke-FileAnalysis $unknownFile $null; $unsafe.Security='Suspicious'
        $packed=Invoke-FileAnalysis $unknownFile $null; $packed.ArcType='.zip'
        Invoke-UnknownIdentification @($protected,$keys,$unsafe,$packed)
        Assert ($script:lookupCalls -eq $before -and @($protected,$keys,$unsafe,$packed | Where-Object IdentificationStatus -ne 'Skipped').Count -eq 0) 'Protected files, keys, suspicious files and archives are not submitted'
        $program=Invoke-FileAnalysis (New-Fixture 'identification-library/disguised.blob' ([byte[]]@(0x7f,0x45,0x4c,0x46,0,0,0,0))) $null
        Invoke-UnknownIdentification @($program)
        Assert ($program.Security -eq 'Malicious' -and $program.IdentificationStatus -eq 'Skipped' -and $script:lookupCalls -eq $before) 'Unknown executable contents are detected before any online identification request'
        $script:OnlineCache=@{}; $S.Console='SNES'
        $script:lookupAnswer=New-IdentificationAnswer $biosFile '[BIOS] PlayStation.bin' 'Sony PlayStation'
        $filtered=Invoke-FileAnalysis $biosFile $null; Invoke-UnknownIdentification @($filtered)
        Assert ($filtered.Category -eq 'Other_Console' -and -not $filtered.BiosMovable) 'Online firmware cannot bypass console filter'
        $S.Console='All'; $S.IdentifyUnknown=$false; $script:IdentificationStop=''
        $script:ScanErrors = New-Object Collections.ArrayList; [void]$script:ScanErrors.Add('Synthetic unreadable folder')
        $clue.IdentificationReason='<script>alert(1)</script>'
        $script:ScanRunStamp=Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'
        $reportOutput=@(Export-IdentificationReport @($identified,$clue,$miss))
        $diagnosticCsv=[IO.Path]::ChangeExtension($script:LastIdentificationReport,'.csv')
        $reportRows=@(Import-Csv -LiteralPath $diagnosticCsv)
        Assert ($reportOutput.Count -eq 0 -and $reportRows.Count -eq 4) 'Dated diagnostics include results and unreadable paths without pipeline pollution'
        Assert ((Get-Content -LiteralPath $script:LastIdentificationReport -Raw) -match '&lt;script&gt;' -and $reportRows[0].ScriptSHA256 -and $reportRows[0].RunDate) 'Diagnostic HTML escapes remote clues and records run/script version'
        Assert ($reportRows[1].SuggestedImprovement -match 'profile' -and $reportRows[1].OnlinePlatform) 'Unsupported platform report gives actionable local improvement evidence'
        $oldReport=$script:LastIdentificationReport
        $script:ScanRunStamp=Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'; Export-IdentificationReport @()
        Assert ((Test-Path -LiteralPath $oldReport) -and $oldReport -ne $script:LastIdentificationReport) 'Later runs preserve prior dated identification reports'
        $script:ScanErrors.Clear()
        $healthy = Invoke-FileAnalysis $file $null; $healthy.ScanFingerprint=Get-Sha256 $file.FullName
        Write-ScanCheckpoint $healthy
        $previousScriptPath=$script:ScriptPath
        $replacement=New-Fixture 'replacement/RomSorter.ps1' ([Text.Encoding]::UTF8.GetBytes('# updated application'))
        $originalContext=Get-ScanContext; $localContext=Get-ScanContext -Local
        $S.IdentifyUnknown=-not $S.IdentifyUnknown
        Assert ((Get-ScanContext) -ne $originalContext -and (Get-ScanContext -Local) -eq $localContext) 'Online identification setting invalidates saved previews but not successful local checks'
        $S.IdentifyUnknown=-not $S.IdentifyUnknown
        $script:ScriptPath=$replacement.FullName
        Assert ((Get-ScanContext -Local) -eq $localContext -and (Get-ScanContext) -ne $originalContext) 'Script replacement preserves local checks but invalidates old move previews'
        Assert ((Read-ScanCheckpoint $file).Resumed) 'Successful unchanged local analysis survives script replacement'
        $script:ScriptPath=$previousScriptPath
        $retryLocal=Invoke-FileAnalysis $unknownFile $null; $retryLocal.ScanFingerprint=Get-Sha256 $unknownFile.FullName
        Write-ScanCheckpoint $retryLocal
        Assert ($null -eq (Read-ScanCheckpoint $unknownFile)) 'Unidentified local files are retried after future script improvements'
        $healthy.Header='Invalid'; Write-ScanCheckpoint $healthy
        Assert ($null -eq (Read-ScanCheckpoint $file)) 'Invalid/incomplete local analyses are retried, not treated as finished'
        $healthy=Invoke-FileAnalysis $file $null; $healthy.ScanFingerprint=Get-Sha256 $file.FullName
        Write-ScanCheckpoint $healthy
        $legacy=Import-Clixml -LiteralPath (Get-CheckpointPath $file.FullName); $legacy.PSObject.Properties.Remove('Schema')
        Write-AtomicClixml $legacy (Get-CheckpointPath $file.FullName)
        Assert ($null -eq (Read-ScanCheckpoint $file)) 'Legacy checkpoints refresh safely once instead of assuming schema compatibility'
        Write-ScanCheckpoint $healthy
        $movedFile=Join-Path $S.RootFolder 'organized.nes'; Move-OneFile $file.FullName $movedFile $healthy.ScanFingerprint
        try {
            $healthy.Target=$movedFile; Copy-MovedCheckpoint $healthy
            Assert ((Read-ScanCheckpoint (Get-Item -LiteralPath $movedFile)).Resumed) 'Hash-safe sorted files retain local progress at their new path'
        } finally { Move-OneFile $movedFile $file.FullName $healthy.ScanFingerprint }
        $S.IdentifyUnknown=$true
        $script:OnlineCache=@{}; $script:lookupAnswer=New-IdentificationAnswer $unknownFile
        $pipeline=@(Invoke-Scan)
        $pipelineUnknown=$pipeline | Where-Object FileName -eq 'mystery.blob'
        Assert ($pipelineUnknown.Console -eq 'MD' -and $pipelineUnknown.IdentificationStatus -eq 'Identified' -and $pipelineUnknown.HashMatch) 'Actual scan integrates fallback before verification and sort planning'
        Assert ((Test-Path -LiteralPath $script:LastIdentificationReport)) 'Actual check automatically emits a dated improvement report'
        $historyBefore=@(Get-ChildItem -LiteralPath (Join-Path (Get-WorkDir) 'reports') -Filter 'Preview-*.html').Count
        [void](Export-Report $pipeline); [void](Export-Report $pipeline)
        Assert (@(Get-ChildItem -LiteralPath (Join-Path (Get-WorkDir) 'reports') -Filter 'Preview-*.html').Count -eq $historyBefore+2) 'Regular CSV/HTML reports also preserve separate dated history'
        $realRest=(Get-Item Function:Invoke-RestMethod -ErrorAction SilentlyContinue)
        function Invoke-RestMethod { param($Uri,$Headers,$Method,$TimeoutSec,[switch]$UseBasicParsing)
            $script:requestedUri=$Uri
            [pscustomobject]@{ signature=[pscustomobject]@{ rom=[pscustomobject]@{name='Reference.bin';sha1='a'*40;size=123;signatureSource='TOSEC'};game=[pscustomobject]@{system='Sony PlayStation';category='BIOS'} }; platform=[pscustomobject]@{name='Sony PlayStation'} }
        }
        try {
            $parsed=& $realLookup ('b'*32)
            Assert ($parsed.Status -eq 'Found' -and $parsed.SHA1 -eq ('a'*40) -and $parsed.Length -eq 123 -and $parsed.GameCategory -eq 'BIOS') 'Documented Hasheous response exposes strong hash, size, platform and firmware fields'
            Assert ($script:requestedUri -eq "https://hasheous.org/api/v1/Lookup/ByHash/md5/$('b'*32)") 'Identification request transmits only hash, never filename or contents'
        } finally {
            if ($realRest) { Set-Item Function:Invoke-RestMethod $realRest.ScriptBlock } else { Remove-Item Function:Invoke-RestMethod }
        }
    } finally {
        Set-Item Function:Invoke-HasheousLookup $realLookup
        Remove-Item Function:New-IdentificationAnswer
        $S.RootFolder=$savedRoot; $S.IdentifyUnknown=$false; $S.Console='All'; $script:IdentificationStop=''
        if ($previousScriptPath) { $script:ScriptPath=$previousScriptPath }
    }
    Assert ((Get-ProgressEstimate 50 100 10 5).Percent -eq 50) 'Progress percentage reflects measured completed work'
    Assert ((Get-ProgressEstimate 50 100 10 5).SecondsRemaining -eq 10) 'ETA uses measured rate and remaining work'
    Assert ((Get-ProgressEstimate 1 100 1 5).SecondsRemaining -eq -1) 'ETA waits for a warm-up sample'
    Assert ((Get-ProgressEstimate 0 100 10 0).SecondsRemaining -eq -1) 'No work/rate means unknown ETA, not division by zero'
    Assert ((Get-ProgressEstimate 5 -1 10 1).Percent -eq -1) 'Unknown totals do not invent percentages'
    Assert ((Get-ProgressEstimate 5 10 10 1 $true).SecondsRemaining -eq -1) 'Dynamic archive queues and remote waits do not invent ETA'
    Assert ((Get-ProgressEstimate 110 100 10 5).Percent -eq 100) 'Progress is bounded to 100 percent'
    Assert ((Get-ProgressEstimate -5 100 10 0).Percent -eq 0) 'Progress is bounded below at zero'
    Assert ((Format-ProgressTime 90061) -eq '25:01:01') 'Elapsed time does not wrap after 24 hours'
    $liveProbe = (Get-Item Function:Test-LiveProgress).ScriptBlock
    $script:progressEvents = New-Object Collections.ArrayList
    function Test-LiveProgress { $true }
    function Write-Progress {
        param($Id,$ParentId,$Activity,$Status,$CurrentOperation,$PercentComplete,$SecondsRemaining,[switch]$Completed)
        [void]$script:progressEvents.Add([pscustomobject]@{ Id=$Id; ParentId=$ParentId; Activity=$Activity; Status=$Status; Current=$CurrentOperation; Percent=$PercentComplete; Remaining=$SecondsRemaining; Completed=[bool]$Completed })
    }
    try {
        $progressOutput = @(Invoke-ProgressTask 'Progress test' {
            Update-RomProgress -Phase 'Measured bytes' -Done 0 -Total 2MB -Unit bytes -Force
            $script:byteProgressFile = New-Fixture 'progress/hash.bin' (New-Object byte[] (2MB))
            $hash = Get-Sha256 $script:byteProgressFile.FullName
            $allHashes = @(Get-RomHashes $script:byteProgressFile.FullName)
            Assert ($allHashes.Count -eq 4 -and $hash -eq $allHashes[3]) 'Streamed progress-aware hashes preserve every algorithm'
            Set-ProgressCounter 'Hashed' 1
            [pscustomobject]@{ Hash=$hash }
        })
        Assert ($progressOutput.Count -eq 1 -and $progressOutput[0].Hash) 'Progress helpers do not contaminate successful pipeline output'
        Assert (@($script:progressEvents | Where-Object { $_.Id -eq 72 -and $_.Activity -eq 'Verifying SHA256' -and -not $_.Completed -and $_.Percent -ge 0 }).Count -gt 0) 'Large-file SHA256 emits real byte progress'
        Assert (@($script:progressEvents | Where-Object { $_.Id -eq 71 -and $_.ParentId -eq 70 }).Count -gt 0) 'Stage progress is nested under overall task'
        Assert (@($script:progressEvents | Where-Object { $_.Id -eq 72 -and $_.ParentId -eq 71 }).Count -gt 0) 'File progress is nested under current stage'
        Assert ($script:LastProgressSummary.Counters['Hashed'] -eq 1 -and $script:LastProgressSummary.Status -eq 'Finished') 'Task summary records truthful counts and completion'
        Assert ($null -eq $script:RomProgress) 'Completed task clears its progress frame'
        Invoke-ProgressTask 'Aggregate bytes' {
            Update-RomProgress -Phase 'Local checks' -Done 1MB -Total 4MB -Unit bytes -Force
            $script:RomProgress.TrackedPath = $script:byteProgressFile.FullName
            $script:RomProgress.ByteBase = 1MB; $script:RomProgress.TrackedLength = 2MB
            Update-FileProgress 'Verifying SHA256' $script:byteProgressFile.FullName 1MB 2MB
            Assert ($script:RomProgress.Done -eq 2MB -and $script:RomProgress.Unit -eq 'bytes') 'Current-file byte progress advances aggregate scan work without changing units'
            $outerFrame = $script:RomProgress
            Assert-Throws { Invoke-ProgressTask 'Nested failure' { throw 'nested failure' } } 'nested failure' 'Nested failures remain visible to callers'
            Assert ([object]::ReferenceEquals($outerFrame,$script:RomProgress)) 'Nested failures restore the enclosing task frame'
        }
        $script:progressEvents.Clear()
        Invoke-ProgressTask 'Throttling' {
            foreach ($n in 1..100) { Update-RomProgress -Phase 'Loop' -Done $n -Total 100 }
        }
        Assert (@($script:progressEvents | Where-Object { $_.Id -eq 71 -and $_.Activity -eq 'Loop' -and -not $_.Completed }).Count -lt 20) 'Fast loops throttle screen redraws rather than print per file'
        $script:progressEvents.Clear()
        Assert-Throws { Invoke-ProgressTask 'Failure' { Update-RomProgress -Phase 'Before failure' -Indeterminate; throw 'synthetic progress failure' } } 'synthetic progress failure' 'Progress preserves operation failures'
        Assert ($null -eq $script:RomProgress -and $script:LastProgressSummary.Status -eq 'Stopped / incomplete') 'Failure clears bars without claiming success'
        Assert (@($script:progressEvents | Where-Object Completed).Count -eq 3) 'All owned progress IDs are completed on failure'
        $script:stageProbe = @()
        Invoke-ProgressTask 'Stage test' {
            $prior = $script:RomWorkflow; $script:RomWorkflow = $script:RomProgress
            try {
                Invoke-ProgressTask 'Unpacking' { Set-ProgressCounter 'Extracted' 2 }
                Invoke-ProgressTask 'Checking' {
                    Set-ProgressCounter 'Warnings' 1
                    Update-RomProgress -Phase 'Waiting for scanner' -Indeterminate -Force
                    $script:stageProbe = @($script:RomWorkflow.StageStates)
                }
                Invoke-ProgressTask 'Sorting' { Set-ProgressCounter 'Moved' 3 }
            } finally { $script:RomWorkflow = $prior }
        } -Stages @('Unpacking','Checking','Sorting')
        Assert ($script:stageProbe[0] -eq 'Finished' -and $script:stageProbe[1] -eq 'Running' -and $script:stageProbe[2] -eq 'Waiting') 'Workflow tracker differentiates complete, active and pending stages'
        Assert ($script:LastProgressSummary.Counters['Unpacking Extracted'] -eq 2 -and $script:LastProgressSummary.Counters['Sorting Moved'] -eq 3 -and $script:LastProgressSummary.Counters['Warnings'] -eq 1) 'Full workflow aggregates results and warning counts'
        $script:progressEvents.Clear()
        Invoke-ProgressTask 'Scanner test' {
            $exe = (Get-Process -Id $PID).Path
            $probe = Invoke-ProgressProcess $exe @('-NoProfile','-Command',"[Console]::Out.Write('scanner output'); [Console]::Error.Write('scanner error'); Start-Sleep -Milliseconds 550; exit 2") 'Synthetic scanner'
            Assert ($probe.Code -eq 2 -and $probe.Output -match 'scanner output' -and $probe.Output -match 'scanner error') 'Responsive scanner wait preserves output, stderr and exit code'
        }
        Assert (@($script:progressEvents | Where-Object { $_.Id -eq 72 -and $_.Activity -eq 'Synthetic scanner' -and $_.Percent -eq -1 -and $_.Remaining -eq -1 }).Count -gt 0) 'Antivirus waiting is explicitly indeterminate'
        Invoke-ProgressTask 'Rate limit test' {
            $watch = [Diagnostics.Stopwatch]::StartNew(); Wait-RomProgress 0.05 'Test API'
            Assert ($watch.Elapsed.TotalSeconds -ge 0.04 -and $watch.Elapsed.TotalSeconds -lt 2) 'Rate-limit countdown waits for the requested duration'
        }
        function Test-LiveProgress { $false }
        $script:progressEvents.Clear()
        $plainOutput = @(Invoke-ProgressTask 'Plain output test' { Update-RomProgress -Phase 'Plain phase' -Done 1 -Total 2 -Force; 123 })
        Assert ($plainOutput.Count -eq 1 -and $plainOutput[0] -eq 123 -and $script:progressEvents.Count -eq 0) 'Redirected/plain output uses readable status without ANSI bars or pipeline pollution'
        Assert-Throws { Invoke-ProgressTask 'Missing hash' { Get-Sha256 (Join-Path $testRoot 'missing.bin') } } '.*' 'Missing file errors are not swallowed by progress callbacks'
        Assert ($null -eq $script:RomProgress) 'Hash failure restores progress lifecycle'
    } finally { Set-Item Function:Test-LiveProgress $liveProbe; Remove-Item Function:Write-Progress }
    Write-Host "PASS: $passed assertions on PowerShell $($PSVersionTable.PSVersion) ($([Environment]::OSVersion.Platform))" -ForegroundColor Green
} finally {
    $env:APPDATA = $oldAppData; $env:XDG_CONFIG_HOME = $oldXdg
    if ([IO.Directory]::Exists($testRoot)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
