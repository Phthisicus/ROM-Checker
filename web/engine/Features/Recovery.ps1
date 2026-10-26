switch ($request.Action) {
    'history' {
        $history = @(Get-UndoLogs | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Modified = $_.LastWriteTimeUtc.ToString('o')
                Entries = @(Import-Csv -LiteralPath $_.FullName | Where-Object Action -in 'Moved','Extracted' | Select-Object OriginalPath,CurrentPath -Unique).Count }
        })
    }
    { $_ -in 'undo-preview','undo' } {
        $log = @(Get-UndoLogs | Where-Object Name -eq $request.Journal)
        if ($log.Count -ne 1) { throw 'Recovery journal not found.' }
        foreach ($row in @(Import-Csv -LiteralPath $log[0].FullName)) {
            if ($row.OriginalPath) { Assert-WebPath $row.OriginalPath }
            if ($row.CurrentPath) { Assert-WebPath $row.CurrentPath }
        }
        Invoke-UndoLog $log[0] ($request.Action -eq 'undo')
    }
    default { throw "Unsupported recovery action: $($request.Action)" }
}
