$url = 'https://download.microsoft.com/download/6/F/5/6F5FF66C-6775-42B0-86C4-47D41F2DA187/Win8.1AndW2K12R2-KB3191564-x64.msu'
$checksum = 'a8d788fa31b02a999cc676fb546fc782e86c2a0acd837976122a1891ceee42c0'
$output = "C:\Windows\Temp\Win8.1AndW2K12R2-KB3191564-x64.msu"

# Ensure the Windows Update service is running.
Get-Service -Name wuauserv | Start-Service

# Download the update.
(New-Object System.Net.WebClient).DownloadFile($url, $output)

# Validate the checksum.
if ((Get-FileHash -Path $output -Algorithm SHA256).Hash.ToLower() -ne $checksum) {
    Write-Output "Checksum does not match."
    exit 1
}

# Extract the contents of the msu package.
C:\Windows\System32\wusa.exe `
    C:\Windows\Temp\Win8.1AndW2K12R2-KB3191564-x64.msu `
    /extract:C:\Windows\Temp

# Install the cab file wih Dism.
C:\Windows\System32\Dism.exe `
    /online /add-package `
    /PackagePath:C:\Windows\Temp\WindowsBlue-KB3191564-x64.cab `
    /Quiet /NoRestart
# Returns 3010 to signify "reboot required"

# Stop the Windows Update service.
Get-Service -Name wuauserv | Stop-Service
