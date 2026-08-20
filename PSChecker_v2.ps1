#requires -RunAsAdministrator
# =============================================================================
# Windows + Office License Checker & Fixer (PowerShell 2.0 Compatible)
# =============================================================================

# --- Logging ---
function Write-Log {
    param (
        [string]$Message,
        [string]$EntryType = "Information"
    )
    
    $Color = "Green"
    if ($EntryType -eq "Error") { $Color = "Red" }
    elseif ($EntryType -eq "Warning") { $Color = "Yellow" }
    
    Write-Host $Message -ForegroundColor $Color
    
    # Event log (PS 2.0 compatible)
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists("Win10Deploy")) {
            New-EventLog -LogName "Application" -Source "Win10Deploy"
        }
        Write-EventLog -LogName "Application" -Source "Win10Deploy" -EventID 1001 `
            -EntryType $EntryType -Message $Message
    } catch {
        # Silently fail if event log isn't available
    }
}
function Get-WindowsLicense {
    # Use Get-WmiObject for PS 2.0 compatibility
    $licenses = Get-WmiObject -Class SoftwareLicensingProduct -Filter "PartialProductKey is not null"
    foreach ($lic in $licenses) {
        if ($lic.Description -like "*Windows*" -or $lic.Name -like "*Windows*") {
            return $lic
        }
    }
    return $null
}

function IpAdressGet {
    Write-Log "=== Getting IP adress ==="
    $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'"

    foreach ($adapter in $adapters) {
        Write-Log "Network Adapter : $($adapter.Description)" "Warning"
        Write-Log "IP Adress(es)   : $($adapter.IPAddress -join ', ')" "Warning"
        Write-Log "Subnet Mask     : $($adapter.IPSubnet -join ', ')" "Warning"
        Write-Log "Default Gateway : $($adapter.DefaultIPGateway -join ', ')" "Warning"
        Write-Log "MAC Adress      : $($adapter.MACAdress)" "Warning"
        Write-Log ("-" * 50) "Warning"
    }
}

function BIOSGet {
    Write-Log "=== Getting data from BIOS ==="
    Get-WmiObject -Class Win32_BIOS | Select-Object -Property *
}

function CPUGet {
    Write-Log "=== Getting data from CPU ==="
    Get-WmiObject -Class Win32_Processor | Select-Object -Property *
}

function RAMGet {
    Write-Log "=== Getting data from RAM ==="
    Get-WmiObject -Class Win32_PhysicalMemory | ForEach-Object {
        [PSCustomObject]@{
            "Slot"      = $_.DeviceLocator
            "Size(Gb)"  = [math]::round($_.Capacity / 1GB, 1)
            "Frequency" = $_.Speed
            "Vendor"    = $_.Manufacturer.Trim()
        }
    } | Format-Table -AutoSize
}

function VRAMGet {
    Write-Log "=== Getting data from VRAM ==="
    Get-WmiObject -Class Win32_VideoController | ForEach-Object {
        [PSCustomObject]@{
            "Name"     = $_.Name
            "Memory"   = [math]::round($_.AdapterRAM / 1MB, 0)
            "Driver"   = $_.DriverVersion
        }
    } | Format-List
}

function DiskGet {
    Write-Log "=== Getting data about disks ==="
    Write-Log "Physical disks: " "Warning"
    Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {
        [PSCustomObject]@{
            "Model"     = $_.Model
            "Size (GB)" = [math]::round($_.Size / 1GB, 1)
            "Type"      = $_.InterfaceType
        }
    } | Format-Table -AutoSize

    Write-Log "Logical volumes: " "Warning"
    Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 3" | ForEach-Object {
        [PSCustomObject]@{
            "Disk"        = $_.DeviceID
            "Size (GB)"  = [math]::round($_.Size / 1GB, 1)
            "Free (GB)"= [math]::round($_.FreeSpace / 1GB, 1)
        }
    } | Format-Table -AutoSize
}

function SeekObjects {
    Write-Log "=============================================" "Error"
    Write-Log "===    RUNNING FIRST TESTING FUNCTION     ===" "Error"
    Write-Log "=============================================" "Error"
    $AnyConnect = Get-ItemProperty @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    ) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*AnyConnect*" } | Select-Object -First 1

    if ($AnyConnect) {
        Write-Log "[GOOD] Cisco AnyConnect founded."
        Write-Log "Full name: $($AnyConnect.DisplayName)" "Warning"
        Write-Log "Version:   $(AnyConnect.DisplayVersion)"
    } else {
        Write-Log "[BAD] Cisco AnyConnect not founded" "Error"
    }

    Write-Log "==============================================" "Error"
    Write-Log "===    RUNNING SECOND TESTING FUNCTION     ===" "Error"
    Write-Log "==============================================" "Error"
    $Targets = @("AnyConnect", "CryptoPro", "1С:Предприятие", "Total Commander", "Vim", "Chrome")

    $RegPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $Result = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        ForEach-Object {
            $Name = $_.DisplayName

            $IsMatch = $true

            # Uncomment me if you want to seek by list
#            $IsMatch = $false
#            foreach ($Target in $Targets) {
#                if ($Name -like "*$Target*") { $IsMatch = $true; break }
#            }

            if ($IsMatch) {
                $RawDate = $_.InstallDate
                $CleanDate = $RawDate
                $FinalDate = "Unknown"
                if ($RawDate -match '^\d{8}$'){
                    $CleanDate = [datetime]::ParseExact($RawDate, 'yyyyMMdd', $null).ToString('dd.MM.yyyy')
                }

                $InstallDir = $_.InstallLocation
                if ($InstallDir -and (Test-Path -Path $InstallDir)) {
                    $FolderInfo = Get-Item -Path $InstallDir -ErrorAction SilentlyContinue
                    if ($FolderInfo) {
                        $FinalDate = $FolderInfo.CreationTime.ToString('dd.MM.yyyy')
                    }
                }

                [PSCustomObject]@{
                    "Program"           = $Name
                    "Version"           = $_.DisplayVersion
                    "Installation Date" = $FinalDate
                    "Update Date"       = $CleanDate
                    "Manufacturer"      = $_.Publisher
                }
            }
        }
    $Result | Format-Table -AutoSize | Out-String -Width 4096
}




# ===========================================================================================
# 
# Эта программа создана для быстрой и эффективной проверки систем Windows на наличие каких-либо функциональных вещей
# 
# ===========================================================================================
# Возьмём имя ПК
# =========================================================================
# БЛОК 1: ОПРЕДЕЛЕНИЕ ИМЕНИ ПК И ПОИСК ФЛЕШКИ (Исправленный)
# =========================================================================
$ComputerName = $env:COMPUTERNAME
$BiosInfo = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
if ($BiosInfo -and $BiosInfo.PSComputerName) { $ComputerName = $BiosInfo.PSComputerName }

# Корректный поиск флешки через стабильный Win32_LogicalDisk
$UsbDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 2" | Select-Object -First 1

if ($UsbDrive -and $UsbDrive.DeviceID) {
    # .DeviceID вернет букву диска с двоеточием, например "E:"
    $LogPath = "$($UsbDrive.DeviceID)\$ComputerName`_terminal_log.txt"
} else {
    # Если флешка не вставлена, пишем лог на рабочий стол
    $LogPath = "$home\Desktop\$ComputerName`_terminal_log.txt"
}

# Включаем запись ВСЕГО терминала в файл
Start-Transcript -Path $LogPath -Append -Force

if ($Host.UI.RawUI) {
    $Size = $Host.UI.RawUI.BufferSize; $Size.Width = 4000; $Host.UI.RawUI.BufferSize = $Size
}

Write-Log "=== RUN SCANNER ON PC: $ComputerName ==="
if (-not $UsbDrive) { 
    Write-Log "ATTENTION: Flash not found, writing log on Desktop!" "Error" 
} else {
    Write-Host "Log is writing on usb flash: $LogPath"
}


$val = 'n'
Write-Log "We will check Windows and Office?"
while ($true) {
    $choice = Read-Host "Make your choice (y/n)"

    if ($choice -eq 'y' -or $choice -eq 'n') {
        # Если нужно bool: y → $true, n → $false
        $val = ($choice -eq 'y')
        break
    } else {
        Write-Host "Invalid input. Please enter 'y' or 'n'." -ForegroundColor Red
    }
}

Write-Host "Your choice: $choice | Boolean value: $val"

# function for checking Windows and Office licenses
if ($val -eq 'y') {
    Write-Log "=== Starting Windows & Office License Check ==="

    # --- Windows Activation Check ---
    Write-Log "`n --- Windows Activation Check ---" "Warning"

    $License = Get-WindowsLicense

    if ($License -ne $null -and $License.LicenseStatus -eq 1) {
        Write-Log "Windows is already activated (Status: Licensed)"
    } else {
        Write-Log "Windows is NOT activated. Attempting fix..." "Warning"

        # Try OEM firmware key first
        $FirmwareKey = $null
        try {
            $sls = Get-WmiObject -Class SoftwareLicensingService
            $FirmwareKey = $sls.OA3xOriginalProductKey
        } catch {
            # No OEM key available
        }

        if ($FirmwareKey -ne $null -and $FirmwareKey -ne "") {
            Write-Log "Found OEM key: $FirmwareKey"
            # Use slmgr for silent activation
            cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ipk $FirmwareKey | Out-Null
            cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato | Out-Null
            Start-Sleep -Seconds 10
            
            $License = Get-WindowsLicense
        }

        # If still not activated, try KMS client key
        if ($License -eq $null -or $License.LicenseStatus -ne 1) {
            Write-Log "OEM activation failed. Attempting KMS activation..." "Warning"
            
            # Try /ato first (if KMS key already installed)
            cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato | Out-Null
            Start-Sleep -Seconds 5
            
            $License = Get-WindowsLicense
            
            if ($License -eq $null -or $License.LicenseStatus -ne 1) {
                Write-Log "Standard activation failed. Fuck that ant let's move to MAS"

                try {
                    $MasScript = curl.exe -s --doh-url https://1.1.1.1/dns-query https://get.activated.win | Out-String

                    if ($MasScript) {
                        $OsProduct = (Get-WmiObject Win32_OperatingSystem).Caption

                        if ($OsProduct -like "*Server*") {
                            Write-Log "Windows Server detected. Applying KMS38" "Warning"
                            & ([ScriptBlock]::Create($MasScript)) /kms38
                        }
                        else {
                            Write-Log "Windows Desktop detected. Applying HWID" "Information"
                            & ([ScriptBlock]::Create($MasScript)) /hwid
                        }
                    }
                    else {
                        throw "Downloaded MAS script is empty."
                    }
                }
                catch {
                    Write-Log "Failed to execute MAS DoH activation: $_" "Error"

                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $MasScript = Invoke-RestMethod -Uri "https://get.activated.win" -UseBasicParsing
                        & ([ScriptBlock]::Create($MasScript)) /hwid
                    }
                    catch {
                        Write-Log "MAS fallback also failed: $_" "Error"
                    }
                }
            }
        }

        # Final check
        $FinalCheck = Get-WindowsLicense
        if ($FinalCheck -ne $null -and $FinalCheck.LicenseStatus -eq 1) {
            Write-Log "Windows activation SUCCESSFUL"
        } else {
            Write-Log "Windows activation FAILED" "Error"
        }
    }


    # --- Office Activation Check ---
    Write-Log "`n=== Checking Office Licenses ===" "Warning"

    # Use Get-WmiObject for PS 2.0
    $AllLicenses = Get-WmiObject -Class SoftwareLicensingProduct
    $OfficeLicenses = @()
    foreach ($lic in $AllLicenses) {
        if ($lic.Name -like "*Office*" -and $lic.PartialProductKey -ne $null) {
            $OfficeLicenses += $lic
        }
    }

    if ($OfficeLicenses.Count -eq 0) {
        Write-Log "No traditional (C2R/MSI) Office installation detected" "Warning"
    } 
    else 
    {
        $NeedsActivation = $false
        foreach ($lic in $OfficeLicenses) {
            $statusText = switch ($lic.LicenseStatus) {
                0 { "Unlicensed" }
                1 { "Licensed" }
                2 { "OOBGrace" }
                3 { "OOTGrace" }
                4 { "NonGenuineGrace" }
                5 { "Notification" }
                6 { "ExtendedGrace" }
                default { "Unknown" }
            }
            
            if ($lic.LicenseStatus -eq 1) {
                Write-Log "OK: $($lic.Name) - $statusText"
            } else {
                Write-Log "NEEDS ACTIVATION: $($lic.Name) - $statusText" "Warning"
                $NeedsActivation = $true
            }
        }

        if ($NeedsActivation) {
            Write-Log "Attempting Office activation via OSPP..." "Warning"
            
            # Find OSPP.VBS
            $OsppPaths = @(
                "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
                "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS",
                "$env:ProgramFiles\Microsoft Office\Office15\OSPP.VBS",
                "${env:ProgramFiles(x86)}\Microsoft Office\Office15\OSPP.VBS"
            )
            
            $OsppPath = $null
            foreach ($path in $OsppPaths) {
                if (Test-Path $path) {
                    $OsppPath = $path
                    break
                }
            }
            
            # Deep search fallback
            if ($OsppPath -eq $null) {
                $SearchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
                foreach ($root in $SearchRoots) {
                    if (Test-Path $root) {
                        $found = Get-ChildItem -Path $root -Filter "OSPP.VBS" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found -ne $null) {
                            $OsppPath = $found.FullName
                            break
                        }
                    }
                }
            }
            $LocalAttempted = $false

            if ($OsppPath -ne $null) {
                Write-Log "Found OSPP at: $OsppPath"
                
                Write-Log "Current Office status:"
                $statusBefore = cscript //nologo "$OsppPath" /dstatus 2>&1
                foreach ($line in $statusBefore) { Write-Host " $line" }
                
                Write-Log "Running OSPP /act..."
                $actResult = cscript //nologo "$OsppPath" /act 2>&1
                foreach ($line in $actResult) {
                    Write-Log " $line"
                    if ($line -like "*<Product activation successful>*"){
                        $LocalAttempted = $true
                    }
                }
                Start-Sleep -Seconds 5

                if (-not $LocalAttempted) {
                    Write-Log "Direct /act failed. Check for KMS key" "Warning"

                    $OfficeVersion = "16" #default for 16/19/21/365
                    if ($OsppPath -like "*Office15*") { $OfficeVersion = "15" }

                    $GvlkKeys = @{
                    "16_ProPlus"     = "XQNVK-8JYDB-WJ9W3-YJ8YR-WFG99"
                    "16_Standard"    = "JNRGM-WHDWX-FJJG3-K47QV-DRTFM"
                    "16_ProjectPro"  = "YG9NW-3K39V-2T3HJ-93F3Q-G83KT"
                    "16_VisioPro"    = "PD3PC-RHNGV-FXJ29-8JK7D-RJRJK"
                    "16_Access"      = "GNH9Y-D2J4T-FJHGG-QRVH7-QPFDW"
                    "16_Excel"       = "9C2PK-NWTVB-JMPW8-BFT28-7FTBF"
                    "16_Outlook"     = "R69KK-NTPKF-7M3Q4-QYBHW-6MT9B"
                    "16_PowerPoint"  = "J7MQP-HNJ4Y-WJ7YM-PFYGF-BY6C6"
                    "16_Publisher"   = "F47MM-N3XJP-TQXJ9-BP99D-8K837"
                    "16_Word"        = "WXY84-JN2Q9-RBCCQ-3Q3J3-3PFJ6"
                    "15_ProPlus"     = "YC7DK-G2NP3-2QQC3-J6H88-GVGXT"
                    "15_Standard"    = "KBKQT-2NMXY-JJWGP-M62JB-92CD4"
                    }

                    $editionHint = $null
                    foreach ($line in $statusBefore) {
                        if ($line -like "*LICENSE NAME:*") {
                            if ($line -like "*ProPlus*") { $editionHint = "ProPlus" }
                            elseif ($line -like "*Standard*") {$editionHint = "Standard" }
                            elseif ($line -like "*ProjectPro*") {$editionHint = "ProjectPro"}
                            elseif ($line -like "*VisioPro*") {$editionHint = "VisioPro" }
                            break
                        }
                    }
                    $keyTry = $null
                    if ($editionHint -ne $null) {
                        $keyTry = $GvlkKeys["${OfficeVersion}_${editionHint}"]
                    }

                    # Try use ProPlus key
                    if ($keyTry -eq $null) {
                        $keyTry = $GvlkKeys["${OfficeVersion}_ProPlus"]
                        if ($keyTry -ne $null) {
                            Write-Log "Could not detect edition, trying ProPlus GVLK as fallback..." "Warning"
                        }
                    }

                    if ($keyTry -ne $null) {
                        Write-Log "Installing GVLK: $keyTry" "Warning"
                        $inpKeyResult = cscript //nologo "$OsppPath" /inpkey:$keyTry 2>&1
                        foreach ($line in $inpKeyResult) { Write-Host "  $line" }
                        Start-Sleep -Seconds 3
                        
                        # Now retry /act
                        Write-Log "Retrying /act after key installation..."
                        $actRetry = cscript //nologo "$OsppPath" /act 2>&1
                        foreach ($line in $actRetry) { 
                            Write-Host "  $line"
                            if ($line -like "*<Product activation successful>*") {
                                $LocalAttempted = $true
                            }
                        }
                        Start-Sleep -Seconds 5
                    }
                }

                Write-Log "Office status:"
                $statusAfter = cscript //nologo "$OsppPath" /dstatus 2>&1
                foreach ($line in $statusAfter) { Write-Host " $line" }
            } 
            else {
                Write-Log "OSPP.VBS not found. Cannot activate Office automatically." "Warning"
                $C2R = "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
            
                if (Test-Path $C2R) {
                    Write-Log "Triggering C2R update..." "Warning"
                    Start-Process -FilePath $C2R -ArgumentList "/update user" -WindowStyle Hidden
                    Start-Sleep -Seconds 5
                } 
                else {
                    Write-Log "Office C2R not found" "Warning"
                }
            }
            
            <#Write-Log "Still not activated. Checking KMS config..." "Warning"
            if (-not $LocalAttempted) {
                $kmsSet = $false
                foreach ($line in $statusBefore) {
                        if ($line -like "*KMS machine*") {
                            $kmsSet = $true
                            break
                        }
                    }
                    if (-not $kmsSet) {
                        Write-Log "No KMS server configured" "Warning"
                        Write-Log " cscript OSPP.VBS /sethst:your-kms-server" "Warning"
                    }
                }
                
                # Re-check
            # coming MAS
            $AllRecheck = Get-WmiObject -Class SoftwareLicensingProduct
            $OfficeRecheck = @()
            foreach ($lic in $AllRecheck) {
                if ($lic.Name -like "*Office*" -and $lic.PartialProductKey -ne $null) {
                    $OfficeRecheck += $lic
                }
            }
                
            $StillNeeds = $false
            foreach ($lic in $OfficeRecheck) {
                if ($lic.LicenseStatus -ne 1) {
                    $StillNeeds = $true
                    break
                }
            }#>
                
            # Let's come to MAS
            
            if (-not $LocalAttempted) {
                Write-Log "`nAAAAAAAAAAAAAAaaaaaaaa........" "Warning"
                Start-Sleep -Seconds 1
                Write-Log "Fuck that, i'm calling the MAS" "Error"
                
                $MasDownload = $false
                $MasScript = $null
                Write-Log "[1/2] Trying to Invoke-Method" "Warning"
                try {
                    $request = [System.Net.WebRequest]::Create("https://get.activated.win")
                    $request.Timeout = 60000 # 60s
                    $request.ReadWriteTimeout = 60000
                    $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                    Write-Log " Connecting to get.activated.win..." "Warning"
                    $response = $request.GetResponse()
                    $stream = $response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    
                    Write-Log "Downloading..." "Warning"
                    $MasScript = $reader.ReadToEnd()
                    $reader.Close()
                    $stream.Close()
                    $response.Close()

                    if ($MasScript -and $MasScript.Length -gt 1000){
                        Write-Log " Downloaded: $($MasScript.Length) bytes" "Information"
                        $MasDownload = $true
                    } else {
                        throw "Downloaded content too short or empty"
                    }
                }
                catch {
                    Write-Log " Invoke-RestMethod failed: $_" "Error"
                }

                if (-not $MasDownload){
                    Write-Log "[2/2] Trying curl.exe with DoH..." "Warning"
                    try {
                        $curlOutput = curl.exe -s --connect-timeout 10 --max-time 240 `
                        --doh-url https://1.1.1.1/dns-query `
                        -w "`nHTTP_CODE:%{http_code}`nSIZE:%{size_download}`n" `
                        https://get.activated.win 2>&1

                        $httpCode = "000"
                        $size = "0"
                        foreach ($line in $curlOutput){
                            if ($line -like "HTTP_CODE:*") { $httpCode = $line.Replace("HTTP_CODE:","").Trim() }
                            if ($line -like "SIZE:*") { $size = $line.Replace("SIZE:", "").Trim() }
                        }
                        
                        $MasScript = ($curlOutput | Where-Object { $_ -notlike "HTTP_CODE:*" -and $_ -notlike "SIZE:*" }) | Out-String
                        Write-Log " HTTP Status: $httpCode, Size: $size bytes" "Warning"
                        if ($httpCode -eq "200" -and $MasScript -and $MasScript.Length -gt 1000) {
                            Write-Log "    Downloaded: $($MasScript.Length) bytes" "Information"
                            $MasDownload = $true
                        } else {
                            throw "curl failed: HTTP $httpCode, content length: $($MasScript.Length)"
                        }
                    } catch {
                        Write-Log "    curl failed: $_" "Error"
                    }
                }

                if ($MasDownload -and $MasScript -ne $null){
                    Write-Log "MAS Ohook is Running..." "Error"
                    try {
                        & ([ScriptBlock]::Create($MasScript)) /ohook
                        Write-Log "MAS Ohook executed successfully" "Information"
                    } catch {
                        Write-Log "MAS execution failed: $_" "Error"
                    }
                }
                else {
                    Write-Log "MAS download failed on all methods."

                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $MasScript = Invoke-RestMethod -Uri "https://get.activated.win" -UseBasicParsing
                        & ([ScriptBlock]::Create($MasScript)) /ohook
                        Write-Log "MAS Ohook executed successfully" "Information"
                    } 
                    catch {
                        Write-Log "Failed to run MAS via Invoke-RestMethod: $_" "Error"

                        try {
                            $MasScript = curl.exe -s --doh-url https://1.1.1.1/dns-query https://get.activated.win | Out-String

                            if ($MasScript) {
                                & ([ScriptBlock]::Create($MasScript)) /ohook
                                Write-Log "MAS Ohook via DoH executed successfully" "Information"
                            }
                            else {
                                throw "Downloaded script is empty."
                            }
                        }
                        catch {
                            Write-Log "Failed to execute MAS DoH activation: $_" "Error"
                        }
                    }
                }
            }
            # Final check
            $AllFinal = Get-WmiObject -Class SoftwareLicensingProduct
            $OfficeFinal = @()
            foreach ($lic in $AllFinal) {
                if ($lic.Name -like "**Office*" -and $lic.PartialProductKey -ne $null){
                    $OfficeFinal += $lic
                }
            }
            $FinalNeeds = $false
            foreach ($lic in $OfficeFinal) {
                if ($lic.LicenseStatus -ne 1) {
                    $FinalNeeds = $true
                    break
                }
            }

            if (-not $FinalNeeds){
                Write-Log "Office activation successful"
            }
            else {
                Write-Log "Office haven't activated still. We're giving up" "Error"
                Write-Host "note: curl https://get.activated.win - windows"
            }
        }
    }
}

# Обращаемся к Биосу чтобы вывести информацию о нем и о системе
BIOSGet
# Берём IP-адресс устройства
IpAdressGet
# Берём инфу с процессора
CPUGet
# Берём инфу с видеокарты
VRAMGet
# Берём инфу с оперативной памяти
RAMGet
# Берём инфу с дисков
DiskGet

#Запускаем поисковик программ
SeekObjects

Write-Log "`n=== Script completed ==="
Stop-Transcript
