$proc = Get-CimInstance Win32_Process -Filter "Name='DvdScreensaver.exe'"
foreach ($p in $proc) {
    $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner
    [PSCustomObject]@{
        PID    = $p.ProcessId
        User   = $owner.User
        Domain = $owner.Domain
    }
}
