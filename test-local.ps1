# VM Configuration
$VmName = "hertzer-test-vm"
$Distro = "22.04"
$RemoteDir = "/home/ubuntu/bootstrap-repo"

# Helper Functions
function Log($msg) { Write-Host ">> $msg" -ForegroundColor Cyan }
function Success($msg) { Write-Host "OK: $msg" -ForegroundColor Green }
function Fatal($msg) { Write-Host "ERR: $msg" -ForegroundColor Red; exit 1 }

# Clean up existing instance
if (multipass list | Select-String -SimpleMatch $VmName) {
    Log "Purging existing instance..."
    multipass delete $VmName
    multipass purge
}

# Provision new instance
Log "Provisioning Ubuntu $Distro ($VmName)..."
multipass launch $Distro --name $VmName --cpus 2 --memory 2G --disk 5G
if ($LASTEXITCODE -ne 0) { Fatal "VM launch failed." }

# Network Configuration (IPv6 disable & DNS override)
Log "Configuring network overrides..."
$netCmds = @(
    "sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1",
    "sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1",
    "sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1",
    "sudo bash -c ""rm -f /etc/resolv.conf && echo 'nameserver 8.8.8.8' > /etc/resolv.conf"""
)

foreach ($cmd in $netCmds) {
    Invoke-Expression "multipass exec $VmName -- $cmd" | Out-Null
}

# Connectivity Check
Log "Waiting for uplink..."
$maxRetries = 20
$retry = 0
do {
    multipass exec $VmName -- ping -c 1 8.8.8.8 | Out-Null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep 1
    $retry++
} while ($retry -lt $maxRetries)

if ($retry -ge $maxRetries) { Fatal "Network connectivity timed out." }

# SSH Configuration
Log "Preparing environment..."
$sshKey = "$env:USERPROFILE\.ssh\id_ed25519.pub"
if (-not (Test-Path $sshKey)) { $sshKey = "$env:USERPROFILE\.ssh\id_rsa.pub" }
if (-not (Test-Path $sshKey)) { Fatal "SSH public key not found." }

$envConfig = @"
HOSTNAME="$VmName"
TIMEZONE="Europe/Berlin"
DEPLOY_USER="deploy"
SSH_PUB_KEY="$((Get-Content $sshKey -Raw).Trim())"
"@
Set-Content -Path "config.env" -Value $envConfig -Encoding ASCII

# Payload Transfer (Tar method to preserve binaries)
Log "Syncing project files..."
multipass exec $VmName -- mkdir -p $RemoteDir

$tempTar = Join-Path $env:TEMP "deploy_payload.tar"
if (Test-Path $tempTar) { Remove-Item $tempTar }

# Archive local files, excluding git and config
tar --exclude ".git" --exclude "config.env" -cf $tempTar .

# Upload and extract
multipass transfer $tempTar ${VmName}:/tmp/payload.tar
multipass transfer config.env ${VmName}:${RemoteDir}/config.env
multipass exec $VmName -- tar -xf /tmp/payload.tar -C $RemoteDir

# Execution
Log "Executing bootstrap..."
multipass exec $VmName -- sudo apt-get update -qq

# Sanitize scripts (LF conversion) and execute
$execCmd = "find $RemoteDir -type f -name '*.sh' -exec sed -i 's/\r$//' {} \; && sed -i 's/\r$//' $RemoteDir/config.env"
Invoke-Expression "multipass exec $VmName -- bash -c `"$execCmd`""

$setupCmd = "cd $RemoteDir && sudo chown root:root config.env && sudo chmod 600 config.env && chmod +x setup.sh && sudo ./setup.sh"
multipass exec $VmName -- bash -c $setupCmd

# Final Report
$vmIp = multipass info $VmName | Select-String "IPv4" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
Write-Host "----------------------------------------------------"
Success "Deployment Ready: $vmIp"
Write-Host "SSH: ssh deploy@$vmIp -i $env:USERPROFILE\.ssh\id_ed25519"
Write-Host "----------------------------------------------------"