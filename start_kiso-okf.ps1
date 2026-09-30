#kiso-mcp-server.exe -s ecs-okf -H 0.0.0.0 -p 61080
$myHost = "$($env:COMPUTERNAME).local"
$candidateIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and
        $_.IPAddress -notlike '169.254.*' -and
        $_.IPAddress -notlike '172.1[6-9].*' -and
        $_.IPAddress -notlike '172.2[0-9].*' -and
        $_.IPAddress -notlike '172.3[0-1].*'
    } |
    Select-Object -ExpandProperty IPAddress
$myIp = $candidateIps | Where-Object { $_ -like '192.*' } | Select-Object -First 1
if (-not $myIp) {
    $myIp = $candidateIps | Select-Object -First 1
}
$allowedHosts = @($myHost)
if ($myIp) { $allowedHosts += $myIp }
Write-Host ("Starting kiso-mcp-server with -allowedHosts: {0}" -f ($allowedHosts -join ','))
java --add-modules jdk.incubator.vector -jar .\kiso-mcp-server.jar -s ecs-okf -H 0.0.0.0 -p 61080 --allowedHosts ($allowedHosts -join ',')