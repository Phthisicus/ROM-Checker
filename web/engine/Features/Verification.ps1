if ($request.Action -ne 'scan') { throw "Unsupported verification action: $($request.Action)" }
$results = @(Invoke-Scan)
