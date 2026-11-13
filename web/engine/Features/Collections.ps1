$collectionPath = Join-Path (Get-WorkDir) 'collection.xml'
$collectionJson = Join-Path (Get-WorkDir) 'collection.json'
function Set-CollectionProperty($row, [string]$name, $value) {
    $row | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}
function Get-CollectionExplanation($row) {
    $con = Get-Con $row.Console
    $system = if ($con) { $con.Name } else { 'this format' }
    if (-not $row.CheckedUtc) { return 'Console detection is provisional. Verification has not run. No security or integrity clearance is implied.' }
    $reference = if ($row.DatMatch -or $row.HashMatch) { ' A reference fingerprint matches, but identity is separate from integrity and security.' } else { '' }
    if ($row.Header -eq 'Invalid') {
        return "The supported $system structure/header check found an irregularity. Homebrew and modified releases may use unusual structures; this finding alone does not prove the file is unusable.$reference Review the technical findings before using it."
    }
    if ($row.Integrity -eq 'Mismatch') { return "An internal checksum check for $system failed.$reference Keep this file for review rather than assuming it is safe to repair." }
    if ($row.Header -eq 'Valid') { return "Supported $system structure checks passed. This does not guarantee authenticity or safety.$reference" }
    return "No conclusive internal structure result is available for $system. A check may not apply to this format or may be unsupported; this is not a failed header.$reference"
}
function Get-CollectionHold($row) {
    if (-not $row.CheckedUtc) { return 'Verification did not complete.' }
    if (-not (Get-Con $row.Console)) { return 'Console identity is unresolved.' }
    if ($row.Security -ne 'Clean') { return 'Security findings or incomplete protection require review.' }
    if ($S.DefenderScan -and $row.AntivirusStatus -ne 'Completed - no detections') { return 'The enabled antivirus check did not pass.' }
    if ($S.OnlineCheck -ne 'Off' -and $row.OnlineMalwareStatus -notin 'Completed','Not selected by policy') { return 'An enabled online malware check is unavailable or incomplete.' }
    if ($row.Header -eq 'Invalid' -or $row.Integrity -eq 'Mismatch') { return 'An internal structure or checksum finding needs review.' }
    if ($row.IdentificationStatus -in 'Needs review','Error','Deferred','Unsupported platform') { return 'Online identity evidence is conflicting or incomplete.' }
    if ($row.Category -notin 'Original','Hacks_Mods','Translations','Beta_Proto_Sample','PD_Homebrew_Unlicensed','BS_ST','Companion') { return 'This classification is not eligible for automatic organization.' }
    if ($S.RequireDatMatch -and -not ($row.DatMatch -or $row.HashMatch -or $row.Lead)) { return 'A required reference match is missing.' }
    if ($S.Hasheous -ne 'Off' -and -not ($row.DatMatch -or $row.HashMatch -or $row.Lead)) { return 'The configured reference check has no match.' }
    if (-not ($row.DatMatch -or $row.HashMatch -or $row.Header -eq 'Valid' -or $row.Integrity -eq 'OK' -or $row.Lead)) { return 'There is not enough integrity evidence to organize automatically.' }
    return ''
}
function Set-CollectionDependencyEvidence($rows) {
    $byPath = New-PathMap
    foreach ($row in $rows) { $byPath[$row.FullName] = $row }
    foreach ($row in $rows) {
        $complete = $true; $conflict = $false
        if ($script:SetDescExt -contains [IO.Path]::GetExtension($row.FileName).ToLowerInvariant()) {
            try {
                $names = @(Get-SetMembers $row.FullName)
                if (-not $names.Count) { $complete = $false }
                $prefix = Get-DirectoryPrefix (Split-Path $row.FullName)
                foreach ($name in $names) {
                    $full = [IO.Path]::GetFullPath((Join-Path (Split-Path $row.FullName) (Convert-RelativePath $name)))
                    $member = $byPath[$full]
                    if (-not $full.StartsWith($prefix, $script:PathComparison) -or -not $member) { $complete = $false; continue }
                    if ((Get-Top $member).FullName -ne (Get-Top $row).FullName) { $conflict = $true }
                    if ($member.Console -ne '-' -and $row.Console -ne '-' -and $member.Console -ne $row.Console) { $conflict = $true }
                }
            } catch { $complete = $false }
        }
        Set-CollectionProperty $row 'DependenciesComplete' $complete
        Set-CollectionProperty $row 'DependencyConflict' $conflict
    }
    foreach ($unit in @($rows | Group-Object { (Get-Top $_).FullName })) {
        $complete = -not @($unit.Group | Where-Object { -not $_.DependenciesComplete }).Count
        $conflict = [bool]@($unit.Group | Where-Object DependencyConflict).Count
        foreach ($row in $unit.Group) {
            $row.DependenciesComplete = $complete; $row.DependencyConflict = $conflict
        }
    }
}
function Save-Collection($rows) {
    foreach ($row in $rows) {
        Set-CollectionProperty $row 'Explanation' (Get-CollectionExplanation $row)
        Set-CollectionProperty $row 'ConsoleName' $(if (Get-Con $row.Console) { (Get-Con $row.Console).Name } else { 'Unknown / Needs identification' })
        $relative = $row.FullName.Substring((Get-DirectoryPrefix $S.RootFolder).Length).Replace('\','/')
        Set-CollectionProperty $row 'RelativePath' $relative
        $group = (Get-Top $row).CollectionId
        Set-CollectionProperty $row 'GroupId' $group
    }
    [void][IO.Directory]::CreateDirectory((Get-WorkDir))
    for ($attempt = 0; ; $attempt++) {
        try { Write-AtomicClixml @($rows) $collectionPath; break }
        catch [IO.IOException] {
            if ($attempt -ge 5) { throw }
            Start-Sleep -Milliseconds (50 * ($attempt + 1))
        }
    }
    $fields = 'CollectionId','GroupId','OriginalRelative','RelativePath','Console','ConsoleName','ConsoleFolder','FileName','Length',
        'Category','Reason','Notes','Threats','Security','Header','IntegrityStatus','AntivirusStatus','MalwareStatus',
        'Authenticity','DatMatch','HashMatch','DatStrength','IdentificationStatus','IdentificationReason','Sources','OnlineMalwareStatus',
        'SHA256','SHA1','MD5','CRC32','CheckedUtc','Organization','HoldReason','Explanation','Integrity','DupOf',
        'DependenciesComplete','DependencyConflict','CheckPolicy'
    Write-AtomicWebJson @($rows | Select-Object $fields) $collectionJson
}
$previous = @()
if (Test-Path -LiteralPath $collectionPath) { $previous = @(Import-Clixml -LiteralPath $collectionPath | ForEach-Object { $_ }) }
if ($request.Action -eq 'detect') {
    $byPath = New-PathMap
    foreach ($row in $previous) { $byPath[$row.FullName] = $row }
    $inventory = @(Get-SortInventory)
    foreach ($row in $inventory) {
        Assert-WebPath $row.FullName
        $old = $byPath[$row.FullName]
        if ($old -and $old.Length -eq $row.Length -and $old.CheckedUtc -and $old.SHA256 -and (Get-Sha256 $row.FullName) -eq $old.SHA256) {
            # Keep completed evidence only when the physical file still has the same fingerprint.
            continue
        }
        if ($row.Category -notin 'Executable','Archive','BIOS' -and -not $row.Protected) {
            $detected = Get-ConsoleForFile ([IO.FileInfo]::new($row.FullName))
            if ($detected.Con) {
                $row.Console = $detected.Con.Key; $row.ConsoleFolder = $detected.Con.Folder
                $row.Category = 'Unknown_Check_Manually'
            }
        }
        Set-CollectionProperty $row 'CollectionId' $(if ($old) { $old.CollectionId } else { [guid]::NewGuid().ToString('N') })
        Set-CollectionProperty $row 'OriginalRelative' $(if ($old) { $old.OriginalRelative } else { $row.FullName.Substring((Get-DirectoryPrefix $S.RootFolder).Length).Replace('\','/') })
        Set-CollectionProperty $row 'Organization' 'Pending'
        Set-CollectionProperty $row 'HoldReason' ''
        if (-not $row.Protected -and $row.Category -eq 'Protected') { $row.Category = 'Unknown_Check_Manually' }
    }
    $rows = @($inventory | ForEach-Object {
        $old = $byPath[$_.FullName]
        if (-not $_.CollectionId -and $old) { $old } else { $_ }
    })
    # Inventory companion links may point at rows replaced by their completed snapshots above.
    $currentByPath = New-PathMap
    foreach ($row in $rows) { $currentByPath[$row.FullName] = $row }
    foreach ($row in $rows) {
        if ($row.Lead -and $currentByPath.ContainsKey($row.Lead.FullName)) { $row.Lead = $currentByPath[$row.Lead.FullName] }
    }
    # Detection groups dependencies; it is not a verification result.
    Join-Sets $rows
    Save-Collection $rows
    $results = $rows
}
elseif ($request.Action -eq 'verify') {
    if (-not $previous.Count) { throw 'Detect consoles before verifying this collection.' }
    $chosen = @{}
    if ($null -eq $request.Selection) { foreach ($row in $previous) { $chosen[$row.CollectionId] = $true } }
    else {
        $known = @{}; foreach ($row in $previous) { $known[$row.CollectionId] = $true }
        foreach ($id in $request.Selection) {
            if (-not $known.ContainsKey($id)) { throw 'Selection is stale. Refresh the collection before retrying.' }
            $chosen[$id] = $true
        }
    }
    # Expand entire linked units, including nested playlists and companion files.
    $groups = @{}; foreach ($row in $previous) { if ($chosen.ContainsKey($row.CollectionId)) { $groups[(Get-Top $row).CollectionId] = $true } }
    $selected = @($previous | Where-Object { $groups.ContainsKey((Get-Top $_).CollectionId) })
    $script:CollectionSelection = New-PathMap
    $byPath = New-PathMap
    foreach ($row in $selected) {
        Assert-WebPath $row.FullName
        if (-not [IO.File]::Exists($row.FullName)) { throw "File location changed: $($row.FileName). Detect consoles again before verifying." }
        $script:CollectionSelection[$row.FullName] = $true
        $byPath[$row.FullName] = $row
    }
    $verified = @(Invoke-Scan)
    $verificationSummary = $script:LastProgressSummary
    if ($verified.Count -ne $selected.Count) { throw 'Some selected files were skipped. Refresh console detection and review protected or moved files.' }
    foreach ($row in $verified) {
        $old = $byPath[$row.FullName]
        Set-CollectionProperty $row 'CollectionId' $old.CollectionId
        Set-CollectionProperty $row 'OriginalRelative' $old.OriginalRelative
        Set-CollectionProperty $row 'CheckPolicy' ([pscustomobject]@{
            DefenderScan = $S.DefenderScan; OnlineCheck = $S.OnlineCheck; RequireDatMatch = $S.RequireDatMatch
        })
        Set-CollectionProperty $row 'Organization' 'Checked only'
        Set-CollectionProperty $row 'HoldReason' (Get-CollectionHold $row)
        if ($row.HoldReason) { $row.Organization = 'Held for review' }
    }
    Set-CollectionDependencyEvidence $verified
    foreach ($row in $verified) {
        if (-not $row.DependenciesComplete -or $row.DependencyConflict) {
            $row.HoldReason = 'Dependencies are missing, unsafe, or conflicting. The complete unit is kept in place.'
            $row.Organization = 'Held for review'
        }
    }
    if ($request.Organize) {
        # A failed member holds its entire disc/companion unit in place.
        $blocked = @{}
        foreach ($row in $verified) { if ($row.HoldReason) { $blocked[(Get-Top $row).FullName] = $true } }
        foreach ($row in $verified) {
            if ($blocked.ContainsKey((Get-Top $row).FullName)) {
                $row.Organization = 'Held for review'
                if (-not $row.HoldReason) { $row.HoldReason = 'A related file needs review; the set is kept intact.' }
                $row.Target = ''; $row.Action = 'Stays'
            }
        }
        $eligible = @($verified | Where-Object { -not $_.HoldReason })
        if ($eligible.Count) {
            # Collection mode always uses console folders. It never relocates rejects or deletes duplicates.
            $S.Layout = 'ByConsole'; $S.RejectsOutside = $false
            Set-Targets $eligible
            Assert-WebResults $eligible
            if (-not (Test-SortResults $verified)) { throw 'Files changed during verification. No automatic organization was started.' }
            Invoke-Organize $verified
            foreach ($row in $eligible) {
                if ($row.Action -like 'Error*') { $row.Organization = 'Failed'; $row.HoldReason = $row.Action }
                elseif ($row.Action -eq 'Moved') { $row.Organization = 'Organized' }
                elseif (-not $row.Target) { $row.Organization = 'Organized' }
                else { $row.Organization = 'Held for review'; $row.HoldReason = 'The move did not complete. Inspect the recovery journal.' }
            }
            # The legacy engine deliberately retains original paths for journals; collection state uses live locations.
            foreach ($row in $eligible) {
                if ($row.Action -eq 'Moved') { $row.FullName = $row.Target; $row.Folder = Split-Path $row.Target; $row.Target = '' }
            }
        }
    }
    $updated = @{}; foreach ($row in $verified) { $updated[$row.CollectionId] = $row }
    $rows = @($previous | ForEach-Object { if ($updated.ContainsKey($_.CollectionId)) { $updated[$_.CollectionId] } else { $_ } })
    Save-Collection $rows
    $results = $verified
    $script:LastProgressSummary = $verificationSummary
    $script:LastProgressSummary.Counters['Organized'] = @($verified | Where-Object Organization -eq 'Organized').Count
    $script:LastProgressSummary.Counters['Held for review'] = @($verified | Where-Object Organization -eq 'Held for review').Count
    $script:LastProgressSummary.Counters['Warnings'] = @($verified | Where-Object { $_.HoldReason -or $_.Organization -eq 'Failed' }).Count
}
else { throw "Unsupported collection action: $($request.Action)" }
