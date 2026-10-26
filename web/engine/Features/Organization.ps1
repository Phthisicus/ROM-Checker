switch ($request.Action) {
    'inventory' { $results = @(Get-SortInventory); Update-Plan $results }
    'plan' {
        foreach ($review in $request.Reviews) {
            $r = $results | Where-Object FullName -eq $review.Path | Select-Object -First 1
            if (-not $r -or $r.Lead -or $r.Category -eq 'Protected') { throw 'Review must reference an unprotected top-level file in the scan.' }
            switch ($review.Decision) {
                'keep' { $r.Category = 'Kept'; $r.Reason = "Kept by web review. $($r.Reason)" }
                'quarantine' { $r.Category = 'Quarantine'; $r.Reason = "Quarantined by web review. $($r.Reason)" }
                'original' {
                    if ($r.Security -ne 'Clean') { throw 'Security warnings cannot be overridden by the web interface.' }
                    $r.Category = 'Original'; $r.Reason = "Marked original by web review (not independent verification). $($r.Reason)"
                }
                default { throw 'Invalid review decision.' }
            }
        }
        Update-Plan $results
    }
    'apply' {
        Assert-WebResults $results
        if (-not (Test-SortResults $results)) { throw 'Library changed after preview. Run a new scan.' }
        Invoke-Organize $results
        if (@($results | Where-Object { $_.Action -like 'Error*' }).Count) { throw 'Some moves failed. Consult the log and recovery journals.' }
    }
    default { throw "Unsupported organization action: $($request.Action)" }
}
