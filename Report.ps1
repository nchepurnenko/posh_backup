<#
.SYNOPSIS
    Create report with information about content of backup.conf files on servers.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    # path to file with list of servers, delimeter is "\n"
    $File = 'Servers.txt'
)
$servers = Get-Content $File
$reportFile = 'Report.txt'
$content = ""

foreach ($server in $servers){

    if (Test-Path -Path \\$server\ut$\backup.conf) {
        $fileContent = Get-Content -path "\\$server\C$\ut\backup.conf" -raw
        $delimeter = "========$server========`n"
        $content += "$delimeter  $fileContent `n"
    }
    else {
        $delimeter = "========$server========`n"
        $content += "$delimeter ERROR `n"
    }
    Set-Content -Path $reportFile -Value $content
}



