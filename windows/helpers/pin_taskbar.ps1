# Greetings to joeleckert from https://community.spiceworks.com/topic/2165665-pinning-taskbar-items-with-powershell-script


Function Set-PinTaskbar {
    Param (
        [parameter(Mandatory=$True, HelpMessage="Target item to pin")]
        [ValidateNotNullOrEmpty()]
        [string] $Target
        ,
        [Parameter(Mandatory=$False, HelpMessage="Target item to unpin")]
        [switch]$Unpin
    )
    If (!(Test-Path $Target)) {
        Write-Warning "$Target does not exist"
        Break
    }

    $KeyPath1  = "HKCU:\SOFTWARE\Classes"
    $KeyPath2  = "*"
    $KeyPath3  = "shell"
    $KeyPath4  = "{:}"
    $ValueName = "ExplorerCommandHandler"
    $ValueData =
        (Get-ItemProperty `
            ("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\" + `
                "CommandStore\shell\Windows.taskbarpin")
        ).ExplorerCommandHandler

    $Key2 = (Get-Item $KeyPath1).OpenSubKey($KeyPath2, $true)
    $Key3 = $Key2.CreateSubKey($KeyPath3, $true)
    $Key4 = $Key3.CreateSubKey($KeyPath4, $true)
    $Key4.SetValue($ValueName, $ValueData)

    $Shell = New-Object -ComObject "Shell.Application"
    $Folder = $Shell.Namespace((Get-Item $Target).DirectoryName)
    $Item = $Folder.ParseName((Get-Item $Target).Name)

    # Registry key where the pinned items are located
    $RegistryKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    # Binary registry value where the pinned items are located
    $RegistryValue = "FavoritesResolve"
    # Gets the contents into an ASCII format
    $CurrentPinsProperty = ([system.text.encoding]::ASCII.GetString((Get-ItemProperty -Path $RegistryKey -Name $RegistryValue | Select-Object -ExpandProperty $RegistryValue)))
    # Specifies the wildcard of the current executable to be pinned, so that it won't attempt to unpin / repin
    $Executable = "*" + (Split-Path $Target -Leaf) + "*"
    # Filters the results for only the characters that we are looking for, so that the search will function
    [string]$CurrentPinsResults = $CurrentPinsProperty -Replace '[^\x20-\x2f^\x30-\x39\x41-\x5A\x61-\x7F]+', ''

    # Unpin if the application is pinned
    If ($Unpin.IsPresent) {
        If ($CurrentPinsResults -like $Executable) {
            $Item.InvokeVerb("{:}")
        }
    }
    Else {
        # Only pin the application if it hasn't been pinned
        If (!($CurrentPinsResults -like $Executable)) {
            $Item.InvokeVerb("{:}")
        }
    }
    
    $Key3.DeleteSubKey($KeyPath4)
    If ($Key3.SubKeyCount -eq 0 -and $Key3.ValueCount -eq 0) {
        $Key2.DeleteSubKey($KeyPath3)
    }
}