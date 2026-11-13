switch ($request.Action) {
    'unpack' { Invoke-Unpack }
    'cleanup-preview' { $cleanup = @(Get-ArchiveCleanupPlan @(Get-CleanupRecords)) }
    'cleanup' {
        $savedCleanup = Get-Content -LiteralPath (Join-Path $request.SourceDirectory 'cleanup.json') -Raw | ConvertFrom-Json
        $cleanup = @($savedCleanup | ForEach-Object { $_ })
        foreach ($item in $cleanup) { Assert-WebPath $item.Path; Assert-WebPath $item.OriginalPath }
        Invoke-ArchiveCleanup $cleanup
    }
    default { throw "Unsupported archive action: $($request.Action)" }
}
