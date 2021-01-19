# One script to setup a decent Windows environment from a clean install using Chocolatey, by c4ffein

# Should check certificate
$certifAlgorithm = 'sha256RSA'
$certifSubject = 'CN="Chocolatey Software, Inc.", O="Chocolatey Software, Inc.", L=Topeka, S=Kansas, C=US'
$certifIssuer = 'CN=DigiCert SHA2 Assured ID Code Signing CA, OU=www.digicert.com, O=DigiCert Inc, C=US'
$certifThumbprint = "4BF7DCBC06F6D0BDFA8A0A78DE0EFB62563C4D87"


# Start another PowerShell process as Admin if needed
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList ("-ExecutionPolicy Bypass " + $arguments)
    Break
}


function FailedIf {
    If ($args[0]) {
        Write-Host $args[1] -ForegroundColor Yellow
        pause
        exit
    }
}


Write-Host "Downloading Chocolatey install script" -ForegroundColor Red
$chocolateyPS = (New-Object System.Net.WebClient).DownloadData('https://chocolatey.org/install.ps1')
$chocolateyPSString = [System.Text.Encoding]::ASCII.GetString($chocolateyPS)
# Needed as Get-AuthenticodeSignature can only take Unicode Byte Array as -Content
$chocolateyPSUnicodeByteArray = [System.Text.Encoding]::Unicode.GetBytes($chocolateyPSString)


Write-Host "Checking Chocolatey install script certificate" -ForegroundColor Red
$certif = (Get-AuthenticodeSignature -Content $chocolateyPSUnicodeByteArray -SourcePathOrExtension "chocolatey_install.ps1").SignerCertificate
$certif | Format-List
FailedIf ($certif.SignatureAlgorithm.FriendlyName -ne $certifAlgorithm) "Certif Algorithm mismatch. Exiting."
FailedIf ($certif.Subject -ne $certifSubject) "Certif Subject mismatch. Exiting."
FailedIf ($certif.Issuer -ne $certifIssuer) "Certif Issuer mismatch. Exiting."
FailedIf ($certif.Thumbprint -ne $certifThumbprint) "Certif Thumbprint mismatch. Exiting."


Write-Host "Executing Chocolatey install script" -ForegroundColor Red
iex $chocolateyPSString


Write-Host "Installing programs" -ForegroundColor Red
choco install python atom cmder git gh powertoys -y


Write-Host "Installing Python utility packages" -ForegroundColor Red
pip install magic-wormhole


Write-Host "Adding missing shortcuts" -ForegroundColor Red
# Add to Desktop, as it's too complicated for this script to reliably pin to taskbar in Powershell since latest Windows 10
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"
Install-ChocolateyShortcut -ShortcutFilePath ([Environment]::GetFolderPath("Desktop")+"\Cmder.lnk") -TargetPath $Env:SYSTEMDRIVE"\tools\Cmder\Cmder.exe"
Install-ChocolateyShortcut -ShortcutFilePath ([Environment]::GetFolderPath("Desktop")+"\Atom.lnk") -TargetPath $(Convert-Path ($env:LOCALAPPDATA + "\atom\app*\atom.exe"))


echo "[alias]`n  co = checkout`n  ct = commit`n  st = status`n  br = branch`n  type = cat-file -t`n  dump = cat-file -p" > ~/.gitconfig


pause
