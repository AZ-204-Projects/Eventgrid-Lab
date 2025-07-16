# add-packages.ps1
$originalDir = Get-Location
try {
    Set-Location "$PSScriptRoot\EventGridFunctionProj"
    dotnet add package Azure.Messaging.EventGrid
}
catch {
    Write-Error "Script failed: $_"
}
finally {
    Set-Location $originalDir
}