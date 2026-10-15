function Get-TaskSHA256([string]$Path) {
    $taskHasher=[System.Security.Cryptography.SHA256]::Create()
    $taskStream=[System.IO.File]::OpenRead($Path)
    try { return ([System.BitConverter]::ToString($taskHasher.ComputeHash($taskStream))).Replace('-','') }
    finally { $taskStream.Dispose();$taskHasher.Dispose() }
}
