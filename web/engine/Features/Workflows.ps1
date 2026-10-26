if ($request.Action -ne 'workflow') { throw "Unsupported workflow action: $($request.Action)" }
Invoke-Unpack
$unpackSummary = $script:LastProgressSummary
$results = @(Invoke-Scan)
$script:LastProgressSummary.Counters['Unpack warnings'] = [int]$unpackSummary.Counters['Warnings']
$script:LastProgressSummary.Counters['Extracted archives'] = [int]$unpackSummary.Counters['Extracted']
$script:LastProgressSummary.Counters['Warnings'] = [int]$script:LastProgressSummary.Counters['Warnings'] + [int]$unpackSummary.Counters['Warnings']
