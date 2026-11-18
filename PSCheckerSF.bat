<# : PSScript
@echo off
setlocal EnableExtensions EnableDelayedExpansion
:: 2. cd to folder with running code
cd /d "%~dp0"
set "DriveLetter=%~d0"
:: 3. Run ps1 file
echo running Checker...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content '%~f0' | Out-String | Invoke-Expression" 
goto :eof
#>

#
#	 _____	 _					 ___	   _   ____
#	| |__ \	| |		     /\      |   \	  | | |  _ \
#	| |__||	| |		    /  \     | |\ \	  | | | | \ \
#	| |___/	| |		   / /\ \  	 | | \ \  | | | |  \ |
#	| |__ \	| |		  / /__\ \ 	 | |  \ \ | | | |  / |
#	| |__||	| |___	 / ______ \	 | |   \ \| | | |_/ /
#	|_|___/	|_____|	/_/	     \_\ |_|    \___| |____/
#
#

# HIDING OUTPUT INTO FILE, NOT USING CONSOLE

$script:hidden = $false

# Скрываем ли мы вывод консоли


# === Logging ===
function Write-Log {
    # Usage: Write-Log "your-text" "Good"
    param (
        [string]$Message,
        [string]$EntryType = "Information"
    )
        
    # 1. Определяем цвет для консоли на основе переданного EntryType
    if ($EntryType -eq "Good") { $Color = "Green" }
    elseif ($EntryType -eq "Error") { $Color = "Red" }
    elseif ($EntryType -eq "Warning") { $Color = "Yellow" }
    elseif ($EntryType -eq "Cyan") { $Color = "Cyan" }
    else { $Color = "White" }
        
    Write-Host $Message -ForegroundColor $Color
    
    if ($script:hidden){
        # 2. Приводим EntryType к валидному системному типу для Event Log.
        # Если это "Good" или "Cyan", заменим их на стандартный "Information".
        $ValidEventTypes = @("Error", "Warning", "Information", "SuccessAudit", "FailureAudit")
            
        if ($ValidEventTypes -notcontains $EntryType) {
            $SysEntryType = "Information"
        }
        else {
            $SysEntryType = $EntryType
        }
            
        # Запись в Event log
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists("Win10Deploy")) {
                New-EventLog -LogName "Application" -Source "Win10Deploy"
            }
            # Передаем в параметр -EntryType безопасную переменную $SysEntryType
            Write-EventLog -LogName "Application" -Source "Win10Deploy" -EventID 1001 `
                -EntryType $SysEntryType -Message $Message
        }
        catch {
            # Тихое замалчивание ошибок записи в лог
        }
    }
}

# Пробуем в параллельные вычисления
function Invoke-ParallelWithOrder {
    param(
        [Parameter(Mandatory=$true)]
        [array]$ScriptBlocks,
        [int]$ThrottleLimit = [Environment]::ProcessorCount,
        [bool]$UseFullOutput = $false        # <-- новый параметр
    )

    $ExcludeFunctions = @('Invoke-ParallelWithOrder', 'prompt', 'TabExpansion2', 'TabExpansion')
    $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    Get-ChildItem Function:\ | Where-Object { $ExcludeFunctions -notcontains $_.Name } | ForEach-Object {
        try {
            $ISS.Commands.Add(
                [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
                    $_.Name, $_.Definition
                )
            )
        } catch { }
    }

    $Pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $ISS, $Host)
    $Pool.Open()

    $LaunchOrder = $ScriptBlocks | Sort-Object LaunchWeight -Descending

    $Jobs = @()
    foreach ($Task in $LaunchOrder) {
        $PS = [powershell]::Create()
        $PS.RunspacePool = $Pool
        # ВТОРОЙ аргумент — флаг -On
        [void]$PS.AddScript($Task.Block.ToString()).AddArgument($Task.OutputIndex).AddArgument($UseFullOutput)
        $Jobs += [PSCustomObject]@{
            OutputIndex = $Task.OutputIndex
            Name        = $Task.Name
            PS          = $PS
            Handle      = $PS.BeginInvoke()
        }
    }

    $Results = foreach ($Job in $Jobs) {
        $outObj = $null
        try {
            $Out = $Job.PS.EndInvoke($Job.Handle)
            if ($Job.PS.Streams.Error.Count -gt 0) {
                $errText = ($Job.PS.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
                $outObj = [PSCustomObject]@{
                    Index    = $Job.OutputIndex
                    Messages = @(@{ Message = "ERROR in $($Job.Name): $errText"; EntryType = "Error" })
                }
            }
            elseif ($null -ne $Out) {
                foreach ($Item in @($Out)) {
                    if ($null -ne $Item -and $Item.PSObject.Properties['Index']) { $outObj = $Item }
                }
            }
            else {
                $outObj = [PSCustomObject]@{
                    Index    = $Job.OutputIndex
                    Messages = @(@{ Message = "EMPTY OUTPUT in $($Job.Name)"; EntryType = "Warning" })
                }
            }
        }
        catch {
            $outObj = [PSCustomObject]@{
                Index    = $Job.OutputIndex
                Messages = @(@{ Message = "EXCEPTION in $($Job.Name): $_"; EntryType = "Error" })
            }
        }
        finally { $Job.PS.Dispose() }
        $outObj
    }

    $Pool.Close()
    $Pool.Dispose()

    return ($Results | Sort-Object Index)
}

# Функция, берущая IP адресс системы
function IpAdressGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting IP adress ==="; EntryType = "Cyan" })
    if ($On) {
        $Raw = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Raw; EntryType = "Information" })
    }        
    else {
        $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'"
        foreach ($adapter in $adapters) {
            [void]$Messages.Add(@{ Message = "Network Adapter : $($adapter.Description)"; EntryType = "Information" })
            [void]$Messages.Add(@{ Message = "IP Adress(es)   : $($adapter.IPAddress -join ', ')"; EntryType = "Information" })
            [void]$Messages.Add(@{ Message = "Subnet Mask     : $($adapter.IPSubnet -join ', ')"; EntryType = "Information" })
            [void]$Messages.Add(@{ Message = "Default Gateway : $($adapter.DefaultIPGateway -join ', ')"; EntryType = "Information" })
            [void]$Messages.Add(@{ Message = "MAC Adress      : $($adapter.MACAdress)"; EntryType = "Information" })
            [void]$Messages.Add(@{ Message = " "; EntryType = "Information" })
        }
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}

# Функция, сканирующяа сетевые адаптеры
function NetAdapterGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data about network adapters ==="; EntryType = "Cyan" })
    if ($On) {
        $Raw = Get-WmiObject -Class Win32_NetworkAdapter | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Raw; EntryType = "Information" })
    }        
    else {
        $Data = Get-WmiObject -Class Win32_NetworkAdapter -Filter "PhysicalAdapter = True" | ForEach-Object {
            New-Object PSObject -Property @{
                "Name"        = $_.Name
                "DeviceID"    = $_.DeviceID
                "MACAddress"   = $_.MACAddress
                "AdapterType" = $_.AdapterType
                "NetEnabled"  = $_.NetEnabled
            }
        } | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Data; EntryType = "Information" })
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}


# Функция, берущая данные из BIOS
function BIOSGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data from BIOS ==="; EntryType = "Cyan" })
    if ($On) {
        $Raw = Get-WmiObject -Class Win32_BIOS | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Raw; EntryType = "Information" })
    }        
    else {
        $Data = Get-WmiObject -Class Win32_BIOS | ForEach-Object {
            New-Object PSObject -Property @{
                "ComputerName" = $_.PSComputerName
                "Name"         = $_.Name
                "ReleaseDate"  = $_.ReleaseDate
                "SerialNumber" = $_.SerialNumber
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Data; EntryType = "Information" })
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}


# Функция, берущая данные от процессора
function CPUGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data from CPU ==="; EntryType = "Cyan" })
    if ($On) {
        $Raw = Get-WmiObject -Class Win32_Processor | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Raw; EntryType = "Information" })
    }        
    else {
        $Data = Get-WmiObject -Class Win32_Processor | ForEach-Object {
            New-Object PSObject -Property @{
                "Name"         = $_.Name
                "ComputerName" = $_.PSComputerName
                "DeviceID"     = $_.DeviceID
                "ProcessorID"  = $_.ProcessorID
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Data; EntryType = "Information" })
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}

# Функция, берущая данные из оперативной памяти
function RAMGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data from RAM ==="; EntryType = "Cyan" })
    if ($On) {
        $Raw = Get-WmiObject -Class Win32_PhysicalMemory | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Raw; EntryType = "Information" })
    }        
    else {
        $Data = Get-WmiObject -Class Win32_PhysicalMemory | ForEach-Object {
            New-Object PSObject -Property @{
                "Slot"       = $_.DeviceLocator
                "Size(Gb)"   = [math]::round($_.Capacity / 1GB, 1)
                "Frequency"  = $_.Speed
                "Vendor"     = $_.Manufacturer.Trim()
                "PartNumber" = $_.PartNumber
            }
        } | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Data; EntryType = "Information" })
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}


# Функция, берущая данные от видеокарты
function VRAMGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data from GPU ==="; EntryType = "Cyan" })
    if ($On) {
        $Raw = Get-WmiObject -Class Win32_VideoController | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Raw; EntryType = "Information" })
    }        
    else {
        $Data = Get-WmiObject -Class Win32_VideoController | ForEach-Object {
            New-Object PSObject -Property @{
                "Name"         = $_.Name
                "Memory"       = [math]::round($_.AdapterRAM / 1MB, 0)
                "Driver"       = $_.DriverVersion
                "ProcessorID"  = $_.ProcessorID
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Data; EntryType = "Information" })
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}


# Функция, обращающаяся к диску и берущая инфу из него
function DiskGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data about disks ==="; EntryType = "Cyan" })
    if ($On) {
        [void]$Messages.Add(@{ Message = "Physical disks: "; EntryType = "Warning" })
        $RawDisks = Get-WmiObject -Class Win32_DiskDrive | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $RawDisks; EntryType = "Information" })

        [void]$Messages.Add(@{ Message = "Logical volumes: "; EntryType = "Warning" })
        $RawVolumes = Get-WmiObject -Class Win32_LogicalDisk | 
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $RawVolumes; EntryType = "Information" })
    }        
    else {
        [void]$Messages.Add(@{ Message = "Physical disks: "; EntryType = "Warning" })
        $DataDisks = Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {
            New-Object PSObject -Property @{
                "Name"         = $_.Name
                "Model"        = $_.Model
                "Size (GB)"    = [math]::round($_.Size / 1GB, 1)
                "Type"         = $_.InterfaceType
                "PartNumber"   = $_.PartNumber
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $DataDisks; EntryType = "Information" })

        [void]$Messages.Add(@{ Message = "Logical volumes: "; EntryType = "Warning" })
        $DataVolumes = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 3" | ForEach-Object {
            New-Object PSObject -Property @{
                "Disk"         = $_.DeviceID
                "Size (GB)"    = [math]::round($_.Size / 1GB, 1)
                "Free (GB)"    = [math]::round($_.FreeSpace / 1GB, 1)
                "FileSystem"   = $_.FileSystem
                "PartNumber"   = $_.PartNumber
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $DataVolumes; EntryType = "Information" })
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}

function MonitorGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data about monitor ==="; EntryType = "Cyan" })
    if ($On) {
        $Raw = Get-WmiObject -Namespace "root\wmi" -Class "WmiMonitorID" |
                Select-Object -Property * |
                Format-List |
                Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $Raw; EntryType = "Information" })
    }
    else {
        $Monitors = Get-WmiObject -Namespace "root\wmi" -Class "WmiMonitorID"

        $Data = foreach ($Monitor in $Monitors) {
            $Namebytes = $Monitor.UserFriendlyName | Where-Object { $_ -ne 0 }
            $MonitorName = if ($Namebytes) { [System.Text.Encoding]::ASCII.GetString($Namebytes) } else { "Unknown" }

            $Serialbytes = $Monitor.SerialNumberID | Where-Object { $_ -ne 0 }
            $SerialNumber = if ($SerialBytes) { [System.Text.Encoding]::ASCII.GetString($SerialBytes) } else { "Unknown" }
                
            New-Object PSObject -Property @{
                "Model"    = $MonitorName
                "Serial N" = $SerialNumber
                "Part ID"  = $Monitor.InstanceName
            }
        }
        $FormattedData = $Data | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $FormattedData; EntryType = "Information" })
    }
    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}

function PeripheralGet {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n ";     EntryType = "Information"})
    [void]$Messages.Add(@{ Message = "=== Getting data about peripherals ==="; EntryType = "Cyan" })

    $Classes = @{
        "Keyboard" = "Keyboard"
        "Mouse"    = "Mouse"
        "AUDIO"    = "Volume"
        "Printer"  = "PNPPrinters"
    }

    foreach ($Target in $Classes.Keys) {
        [void]$Messages.Add(@{ Message = "`n "; EntryType = "Information" })
        [void]$Messages.Add(@{ Message = "[$Target]:"; EntryType = "Information" })
        $ClassName = $Classes[$Target]
        
        $Devices = Get-WmiObject -Class Win32_PnPEntity -Filter "PNPClass = '$ClassName'" -ErrorAction SilentlyContinue

        if ($Devices) {
            if ($On) {
                $RawDevices = $Devices | 
                    Select-Object -Property * | 
                    Format-List | 
                    Out-String -Width 4096
                [void]$Messages.Add(@{ Message = $RawDevices; EntryType = "Information" })
            }
            else {
                $Result = foreach ($Device in $Devices) {
                    $Model = $Device.FriendlyName
                    if ([string]::IsNullOrEmpty($Model)) { $Model = $Device.Name }
                    $DeviceId = $Device.DeviceId
                    
                    $SerialNumber = "Unknown"

                    if ($Target -eq "Printer") {
                        $SafeName = $Device.Name -replace "'", "''"
                        $WmiPrint = Get-WmiObject -Class Win32_Printer -Filter "Name = '$SafeName'" -ErrorAction SilentlyContinue
                        if ($WmiPrint.SerialNumber) { $SerialNumber = $WmiPrint.SerialNumber }
                    }

                    if ($Device.InstanceId -match '\\([^\\]+)$') { 
                        $PotentialSerial = $Matches[1] 
                        if ($PotentialSerial -notmatch '&') { $SerialNumber = $PotentialSerial } 
                    } 
                    
                    if (($SerialNumber -eq "Unknown" -or $SerialNumber -match '&') -and ($DeviceId -like "*VID_*")) { 
                        $SafeParentId = $Device.Parent -replace '\\', '\\'
                        $ParentDevice = Get-WmiObject -Class Win32_PnPEntity -Filter "DeviceID = '$SafeParentId'" -ErrorAction SilentlyContinue 
                        
                        while ($ParentDevice -and $ParentDevice.DeviceId -notlike "USB\*" -and $ParentDevice.Parent) { 
                            $SafeNextParentId = $ParentDevice.Parent -replace '\\', '\\'
                            $ParentDevice = Get-WmiObject -Class Win32_PnPEntity -Filter "DeviceID = '$SafeNextParentId'" -ErrorAction SilentlyContinue 
                        } 
                        
                        if ($ParentDevice -and $ParentDevice.InstanceId -match '\\([^\\]+)$') { 
                            $UsbSerial = $Matches[1] 
                            if ($UsbSerial -notmatch '&') { 
                                $SerialNumber = $UsbSerial 
                            } 
                        } 
                    } 

                    $Props = @{
                        "Type"          = $Target
                        "Model"         = $Model
                        "Serial number" = $SerialNumber
                        "Device ID"     = $DeviceId
                    }
                    New-Object PSObject -Property $Props
                }

                $FormattedResult = $Result | Format-Table "Type", "Model", "Serial number", "Device ID" -AutoSize | Out-String -Width 4096
                [void]$Messages.Add(@{ Message = $FormattedResult; EntryType = "Information" })
            }
        }
        else {
            [void]$Messages.Add(@{ Message = "  Подключенные устройства не найдены"; EntryType = "Error" })
        }
    }   

    # 3. ПОЛУЧЕНИЕ ДАННЫХ О ФЛЕШКАХ И СЪЕМНЫХ НОСИТЕЛЯХ
    [void]$Messages.Add(@{ Message = "`n "; EntryType = "Information" })
    [void]$Messages.Add(@{ Message = "=== REMOVABLE DISKS ==="; EntryType = "Cyan" })
    
    # Вариант 1: Логические диски
    [void]$Messages.Add(@{ Message = "Logical USB-disks"; EntryType = "Information" })
    $UsbDrives = Get-WmiObject -Class Win32_Volume | Where-Object { $_.DriveType -eq 2 }
    if ($UsbDrives) {
        if ($On) {
            $RawUsbDrives = $UsbDrives | Select-Object -Property * | Format-List | Out-String -Width 4096
            [void]$Messages.Add(@{ Message = $RawUsbDrives; EntryType = "Information" })
        }
        else {
            $Logical = foreach ($Drive in $UsbDrives) {
                New-Object PSObject -Property @{
                    "Disk letter" = $Drive.DriveLetter
                    "Tome"        = $Drive.Label
                    "Filesystem"  = $Drive.FileSystem
                    "Free (GB)"   = [Math]::Round($Drive.FreeSpace / 1GB, 2)
                    "All (GB)"    = [Math]::Round($Drive.Capacity / 1GB, 2)
                } 
            }
            $FormattedLogical = $Logical | Format-Table -AutoSize | Out-String -Width 4096
            [void]$Messages.Add(@{ Message = $FormattedLogical; EntryType = "Information" })
        }
    }
    else {
        [void]$Messages.Add(@{ Message = "Active flash volumes not found"; EntryType = "Gray" })
    }

    # Вариант 2 - Физические USB-накопители
    [void]$Messages.Add(@{ Message = "Physical USB-Drives"; EntryType = "Warning" })
    $UsbDiskDrives = Get-WmiObject -Class Win32_DiskDrive | Where-Object { $_.InterfaceType -eq "USB" }
    if ($UsbDiskDrives) {
        if ($On) {
            $RawUsbDisks = $UsbDiskDrives | Select-Object -Property * | Format-List | Out-String -Width 4096
            [void]$Messages.Add(@{ Message = $RawUsbDisks; EntryType = "Information" })
        }
        else {
            $FormattedPhysical = $UsbDiskDrives | Format-Table Model, Size, DeviceID -AutoSize | Out-String -Width 4096
            [void]$Messages.Add(@{ Message = $FormattedPhysical; EntryType = "Information" })
        }
    }
    else {
        [void]$Messages.Add(@{ Message = "Physical USB-Disks not found"; EntryType = "Gray" })
    }

    return [PSCustomObject]@{
        Index    = $TaskIndex
        Messages = $Messages
    }
}


# Функция поиска требуемых программ
function SeekObjects {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "`n "; EntryType = "Information" })
    [void]$Messages.Add(@{ Message = "=== SYSTEM SCANNER STARTINIG ==="; EntryType = "Cyan" })

    $RegPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $Programs = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }

    # ВНИМАНИЕ: Win32_Product очень медленный (перезапускает MSI для каждого продукта).
    # Если хотите ускорить SeekObjects на порядок — закомментируйте эту строку
    # и берите IdentifyingNumber только из реестра ($Program.ProductID).
    $WmiProducts = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue

    $Result = New-Object System.Collections.ArrayList

    foreach ($Program in $Programs) {
        $Name = $Program.DisplayName
        $RawDate = $Program.InstallDate
        $CleanDate = $RawDate
        if ($RawDate -and $RawDate -match '^\d{8}$') {
            try { $CleanDate = [datetime]::ParseExact($RawDate, 'yyyyMMdd', $null).ToString('dd.MM.yyyy') }
            catch { $CleanDate = $RawDate }
        }

        $FinalDate = "Unknown"
        $InstallDir = $Program.InstallLocation
        if ($InstallDir) {
            $FolderInfo = Get-Item -Path $InstallDir -ErrorAction SilentlyContinue
            if ($FolderInfo) { $FinalDate = $FolderInfo.CreationTime.ToString('dd.MM.yyyy') }
        }

        $SerialNumber = "Unknown"
        if ($Program.DigitalProductId) { $SerialNumber = "Has Digital ID" }
        elseif ($Program.SerialNumber) { $SerialNumber = $Program.SerialNumber }
        elseif ($Program.ProductID)    { $SerialNumber = $Program.ProductID }

        if ($SerialNumber -eq "Unknown" -and $WmiProducts) {
            $WmiMatch = $WmiProducts | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
            if ($WmiMatch -and $WmiMatch.IdentifyingNumber) { $SerialNumber = $WmiMatch.IdentifyingNumber }
        }

        $Result += New-Object PSObject -Property @{
            "Program"           = $Name
            "Version"           = $Program.DisplayVersion
            "Installation Date" = $FinalDate
            "Update Date"       = $CleanDate
            "Manufacturer"      = $Program.Publisher
            "Serial / ProdID"   = $SerialNumber
        }
    }

    $Table = $Result |
             Format-Table -Property "Program","Version","Manufacturer","Installation Date","Update Date","Serial / ProdID" -AutoSize |
             Out-String -Width 4096
    [void]$Messages.Add(@{ Message = $Table; EntryType = "Information" })

    return [PSCustomObject]@{ Index = $TaskIndex; Messages = $Messages }
}

# Функция, запрашивающая лицензию Винды
function Get-WindowsLicense {
    # Use Get-WmiObject for PS 2.0 compatibility
    $licenses = Get-WmiObject -Class SoftwareLicensingProduct -Filter "PartialProductKey is not null"
    # Parsing all licenses to find Windows lic
    foreach ($lic in $licenses) {
        if ($lic.Description -like "*Windows*" -or $lic.Name -like "*Windows*") {
            return $lic
        }
    }
    return $null
}

# Функция проверки и в крайнем случае установки лицензий на офис и винду
function WindowsOfficeCheck {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    [void]$Messages.Add(@{ Message = "=== START ALGORITHM OF CHECKING OFFICE AND WINDOWS ==="; EntryType = "Cyan" })
    [void]$Messages.Add(@{ Message = "=== Checking Windows activation ==="; EntryType = "Information" })

    $License = Get-WindowsLicense
    if ($null -ne $License -and $License.LicenseStatus -eq 1) {
        [void]$Messages.Add(@{ Message = "[GOOD] Windows is already activated (Status: Licensed)"; EntryType = "Good" })
    } else {
        [void]$Messages.Add(@{ Message = "[BAD] Windows is NOT activated."; EntryType = "Error" })
    }

    [void]$Messages.Add(@{ Message = "Windows version"; EntryType = "Information" })
    $WinVer = Get-WmiObject -Class Win32_OperatingSystem |
              Select-Object Caption, Version, BuildNumber |
              Format-List | Out-String -Width 4096
    [void]$Messages.Add(@{ Message = $WinVer; EntryType = "Information" })

    [void]$Messages.Add(@{ Message = "Office version"; EntryType = "Information" })
    $OfficeVer = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
                 Where-Object { $_.DisplayName -like "*Office*" } |
                 Select-Object DisplayName, DisplayVersion |
                 Format-List | Out-String -Width 4096
    [void]$Messages.Add(@{ Message = $OfficeVer; EntryType = "Information" })

    [void]$Messages.Add(@{ Message = "`n=== Checking Office Licenses ==="; EntryType = "Warning" })

    $OfficeLicense = Get-WmiObject -Class SoftwareLicensingProduct `
        -Filter "Name LIKE '%Office%' AND LicenseStatus = 1 AND PartialProductKey IS NOT NULL" |
        Where-Object { $_.Name -like "*Office*" } |
        Select-Object -First 1

    if ($OfficeLicense) {
        [void]$Messages.Add(@{ Message = "[GOOD] Office is activated (Licensed)"; EntryType = "Good" })
        [void]$Messages.Add(@{ Message = "License: $OfficeLicense"; EntryType = "Information" })
    } else {
        [void]$Messages.Add(@{ Message = "[BAD] Office is NOT activated."; EntryType = "Error" })
    }

    return [PSCustomObject]@{ Index = $TaskIndex; Messages = $Messages }
}

function ViPNeTSeek {
    param (
        [switch]$On,
        [int]$TaskIndex = 0
    )
    $Messages = [System.Collections.ArrayList]::new()

    $Pattern        = 'ViPNet|Infotecs|Crypto-Pro|Security-Lab'
    $ProcessPattern = 'ViPNet|Infotecs|Coordinator|CryptoPRO|Crypto-Pro'

    [void]$Messages.Add(@{ Message = "=== VIPNET SEEKING MODULE STARTED"; EntryType = "Cyan" })

    # Registry
    [void]$Messages.Add(@{ Message = "Seeking for ViPNeT in registry"; EntryType = "Information" })
    $UninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($Path in $UninstallPaths) {
        $RegHits = Get-ItemProperty $Path -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -and $_.DisplayName -match $Pattern } |
                   Select-Object DisplayName, DisplayVersion, Publisher, InstallDate,
                                 InstallLocation, UninstallString, QuietUninstallString |
                   Format-List | Out-String -Width 4096
        if ($RegHits.Trim()) { [void]$Messages.Add(@{ Message = $RegHits; EntryType = "Information" }) }
    }

    # Services
    [void]$Messages.Add(@{ Message = "Seeking for ViPNet in services"; EntryType = "Information" })
    $SvcHits = Get-WmiObject Win32_Service `
        -Filter "Name LIKE '%ViPNet%' OR Name LIKE '%Infotecs%' OR DisplayName LIKE '%ViPNet%' OR DisplayName LIKE '%Infotecs%'" `
        -ErrorAction SilentlyContinue |
        Select-Object Name, DisplayName, State, StartMode, StartName, PathName |
        Format-List | Out-String -Width 4096
    if ($SvcHits.Trim()) { [void]$Messages.Add(@{ Message = $SvcHits; EntryType = "Information" }) }

    # Processes  (здесь был баг: $VipnetProc vs $VipnetProcesses)
    [void]$Messages.Add(@{ Message = "Seeking for ViPNet in processes"; EntryType = "Information" })
    $VipnetProcesses = @(Get-Process -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match $ProcessPattern })

    if ($VipnetProcesses.Count -gt 0) {
        $ProcHits = $VipnetProcesses |
            Select-Object Name, Id, Path, Company, ProductVersion, StartTime |
            Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $ProcHits; EntryType = "Information" })

        # Network
        [void]$Messages.Add(@{ Message = "Seeking for ViPNet TCP/UDP connections"; EntryType = "Information" })
        $ProcessIdMap = @{}
        foreach ($Process in $VipnetProcesses) { $ProcessIdMap[[int]$Process.Id] = $true }
        $NetHits = netstat -ano 2>$null | ForEach-Object {
            $Line = $_.Trim()
            if ($Line -match '^(TCP|UDP)\s+(\S+)\s+(\S+)(?:\s+(\S+))?\s+(\d+)$') {
                $PidFound = [int]$Matches[5]
                if ($ProcessIdMap.ContainsKey($PidFound)) {
                    New-Object PSObject -Property @{
                        Protocol       = $Matches[1]
                        LocalAddress   = $Matches[2]
                        ForeignAddress = $Matches[3]
                        State          = if ($Matches[1] -eq 'UDP') { 'N/A' } else { $Matches[4] }
                        OwningProcess  = $PidFound
                    }
                }
            }
        } | Format-List | Out-String -Width 4096
        if ($NetHits.Trim()) { [void]$Messages.Add(@{ Message = $NetHits; EntryType = "Information" }) }
    }

    # File system
    [void]$Messages.Add(@{ Message = "Seeking for ViPNet in file system"; EntryType = "Information" })
    $MaxDepth = 2
    $Roots = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:ProgramData", "$env:LOCALAPPDATA", "$env:APPDATA") |
             Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    $FsHits = foreach ($Root in $Roots) {
        Get-ChildItem $Root -Directory -Recurse -Depth $MaxDepth -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $Pattern } |
            Select-Object FullName, CreationTime, LastWriteTime
    }
    if ($FsHits) {
        $FsStr = $FsHits | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $FsStr; EntryType = "Information" })
    }

    # Firewall  (здесь был баг: $RuleTect vs $RuleText)
    [void]$Messages.Add(@{ Message = "Seeking for ViPNet in firewall rules"; EntryType = "Information" })
    $RuleText = netsh advfirewall firewall show rule name=all 2>$null
    $FwHits = foreach ($Line in $RuleText) {
        if ($Line -match '^(Rule Name|Имя правила)\s*:\s*(.+)$') {
            $CurrentRule = $Matches[2].Trim()
            if ($CurrentRule -match $Pattern) { [PSCustomObject]@{ DisplayName = $CurrentRule } }
        }
    }
    if ($FwHits) {
        $FwStr = $FwHits | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $FwStr; EntryType = "Information" })
    }

    # Certificates
    [void]$Messages.Add(@{ Message = "Seeking for ViPNet certificates"; EntryType = "Information" })
    $CertHits = foreach ($Store in @('Cert:\LocalMachine\My','Cert:\CurrentUser\My')) {
        Get-ChildItem $Store -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Subject -and $_.Subject -match $Pattern) -or
                ($_.Issuer  -and $_.Issuer  -match $Pattern) -or
                ($_.EnhancedKeyUsageList -and $_.EnhancedKeyUsageList.FriendlyName -match $Pattern)
            } |
            Select-Object PSParentPath, Subject, Issuer, Thumbprint, NotBefore, NotAfter, HasPrivateKey, SerialNumber
    }
    if ($CertHits) {
        $CertStr = $CertHits | Format-List | Out-String -Width 4096
        [void]$Messages.Add(@{ Message = $CertStr; EntryType = "Information" })
    }

    # Crypto providers
    [void]$Messages.Add(@{ Message = "Seeking for ViPNet cryptographic providers"; EntryType = "Information" })
    $Csp = certutil -csplist 2>$null | Out-String -Width 4096
    if ($Csp.Trim()) { [void]$Messages.Add(@{ Message = $Csp; EntryType = "Information" }) }

    [void]$Messages.Add(@{ Message = "=== VIPNET SEEKING MODULE FINISHED"; EntryType = "Cyan" })

    return [PSCustomObject]@{ Index = $TaskIndex; Messages = $Messages }
}

# ================================================================================
# ================================================================================
# ================================================================================
# ================================================================================
# ================================================================================
# 
# Эта программа создана для быстрой и эффективной проверки систем Windows на наличие каких-либо функциональных вещей
# 
# ==================================================================================
# ================================================================================
# ================================================================================
# ================================================================================
# ================================================================================

# МОДУЛЬ СКРЫТИЯ ВЫВОДА КОНСОЛИ
$Hidden=$script:hidden
if ($Hidden) {
    Add-Content -Path "$env:TEMP\log.txt" -Value "Start"
    $Source = @"
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
"@ 
    Add-Content -Path "$env:TEMP\log.txt" -Value "LIbs may be connected"
    if (-not ([System.Management.Automation.PSTypeName]'Win32.Win32ShowWindowAsync').Type) {
        $Win32 = Add-Type -MemberDefinition $Source `
            -Name "Win32ShowWindowAsync" `
            -Namespace "Win32" `
            -PassThru
    } else {
        $Win32 = [Win32.Win32ShowWindowAsync]
    }
    Add-Content -Path "$env:TEMP\log.txt" -Value "Class may be connected"
    if ($null -ne $Win32){
        Add-Content -Path "$env:TEMP\log.txt" -Value "API found"
        $hwnd = $Win32::GetConsoleWindow()
        if ($hwnd -ne [System.IntPtr]::Zero) {
            Add-Content -Path "$env:TEMP\log.txt" -Value "Window found"
            $null = $Win32::ShowWindowAsync($hwnd, 0)
        } else {
            Add-Content -Path "$env:TEMP\log.txt" -Value "Window not found"
        }
    }
#    $Win32::ShowWindowAsync((Get-Process -Id $pid).MainWindowHandle, 0)
}

Add-Content -Path "$env:TEMP\log.txt" -Value "We hope code is hidden"





# =========================================================================
# БЛОК 1: ОПРЕДЕЛЕНИЕ ИМЕНИ ПК И ПОИСК ФЛЕШКИ
# =========================================================================
Write-Log "PSChecker version: 6"
$ComputerName = $env:COMPUTERNAME
$BiosInfo = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
if ($BiosInfo -and $BiosInfo.PSComputerName) { $ComputerName = $BiosInfo.PSComputerName }

# Текущее время и прочая хуйня
$localTime = Get-Date -Format "HHmmss"
try {
    $webCli = New-Object System.Net.WebClient
    $WebReq = $webCli.Downloadstring("http://worldtimeapi.org")
    if ($WebReq -match '"utc_datetime":"([^"]+)"') {
        $worldTime = [DateTime]$matches[1]
        $networkStatus = "Synchronized through network"
    }
    else {
        throw "Haven't got world time"
        $worldTime = "NO"
    }
}
catch {
    $worldTime = "NO"
    $networkStatus = "No network / NetError"
    Write-Log "No network or we have no connection $_"
}
if ($worldTime -ne "NO"){
    Write-Log "WORLD TIME RIGHT NOW: $worldTime" "Cyan"
    Write-Log "LOCAL TIME RIGTH NOW: $localTime" "Cyan"
} 


# Поиск флешки
$UsbDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 2" | Select-Object -First 1

if ($UsbDrive -and $UsbDrive.DeviceID) {
    # Безопасное объединение: DeviceID (например, "E:") + имя файла
    $LogPath = Join-Path -Path $UsbDrive.DeviceID -ChildPath "${ComputerName}_${localTime}_log.txt"
}
else {
    # Добавлен пропущенный слэш перед именем файла
    $LogPath = Join-Path -Path "$home\Desktop" -ChildPath "${ComputerName}_${localTime}_log.txt"
}

# Включаем запись терминала в файл
Start-Transcript -Path $LogPath -Append -Force

# Безопасное изменение размера буфера только если доступен GUI-интерфейс
if ($Host.UI.RawUI -and $Host.Name -eq 'ConsoleHost') {
    $Size = $Host.UI.RawUI.BufferSize
    $Size.Width = 120 # 4000 слишком много для логов, 120-150 оптимально
    $Host.UI.RawUI.BufferSize = $Size
}

# Проверка существования функции Write-Log (чтобы не было ошибок, если она не объявлена выше)
function Write-LogLocal ($Message, $Color) {
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Color
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

Write-LogLocal "=== RUN SCANNER ON PC: $ComputerName ===" "Cyan"
if (-not $UsbDrive) { 
    Write-LogLocal "ATTENTION: USB Flash not found, writing log on Desktop!" "Red" 
}
else {
    Write-Host "Log is writing on usb flash: $LogPath"
}
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================





# Режим вывода
$UseFullOutput = $false

if ($Hidden) {
    $UseFullOutput = $true
    Write-Log "=== HIDDEN MODE: full output (-On) enabled automatically ===" "Cyan"
}
else {
    $answer = Read-Host "Get extended (-On) data for all subsystems? This significantly increases output size (y/n)"
    if ($answer -match '^(y|yes|д|да)$') {
        $UseFullOutput = $true
        Write-Log "=== User chose FULL output (-On) ===" "Cyan"
    }
    else {
        $UseFullOutput = $false
        Write-Log "=== User chose SUMMARY output (-On disabled) ===" "Cyan"
    }
}
# Определение задач по порядку вывода
# OutputIndex — порядок вывода
# LaunchWeight — приоритет запуска (тяжёлые раньше)
$TaskBlocks = @(
    [PSCustomObject]@{ Name='WindowsOfficeCheck'; LaunchWeight=30;  OutputIndex=0;  Block={ param($o,$f) WindowsOfficeCheck -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='IpAdressGet';        LaunchWeight=5;   OutputIndex=1;  Block={ param($o,$f) IpAdressGet        -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='NetAdapterGet';      LaunchWeight=5;   OutputIndex=2;  Block={ param($o,$f) NetAdapterGet      -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='CPUGet';             LaunchWeight=10;  OutputIndex=3;  Block={ param($o,$f) CPUGet             -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='VRAMGet';            LaunchWeight=10;  OutputIndex=4;  Block={ param($o,$f) VRAMGet            -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='RAMGet';             LaunchWeight=10;  OutputIndex=5;  Block={ param($o,$f) RAMGet             -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='DiskGet';            LaunchWeight=70;  OutputIndex=6;  Block={ param($o,$f) DiskGet            -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='BIOSGet';            LaunchWeight=90;  OutputIndex=7;  Block={ param($o,$f) BIOSGet            -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='MonitorGet';         LaunchWeight=15;  OutputIndex=8;  Block={ param($o,$f) MonitorGet         -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='PeripheralGet';      LaunchWeight=40;  OutputIndex=9;  Block={ param($o,$f) PeripheralGet      -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='SeekObjects';        LaunchWeight=100; OutputIndex=10; Block={ param($o,$f) SeekObjects        -TaskIndex $o -On:$f } }
    [PSCustomObject]@{ Name='ViPNeTSeek';         LaunchWeight=95;  OutputIndex=11; Block={ param($o,$f) ViPNeTSeek         -TaskIndex $o -On:$f } }
)

Write-Log "=== SCAN Start (ThrottleLimit = $([Environment]::ProcessorCount), FullOutput = $UseFullOutput) ===" "Cyan"
$Results = Invoke-ParallelWithOrder -ScriptBlocks $TaskBlocks -UseFullOutput $UseFullOutput
Write-Log "=== SCAN Start (ThrottleLimit = $([Environment]::ProcessorCount)) ===" "Cyan"
$Results = Invoke-ParallelWithOrder -ScriptBlocks $TaskBlocks

foreach($Result in ($Results | Sort-Object Index)) {
    foreach ($Msg in $Result.Messages) {
        Write-log $Msg.Message $Msg.EntryType
    }
}



while ($true) {
    Write-Log "         ." "Cyan"
    Write-Log "        .." "Cyan"
    Write-Log "       ..." "Cyan"
    Write-Log "      ...." "Cyan"
    Write-Log "     ....." "Cyan"
    Write-Log "    ......" "Cyan"
    Write-Log "   ......." "Cyan"
    Write-Log "  ........" "Cyan"
    Write-Log " ........." "Cyan"
    Write-Log ".........." "Cyan"
    Write-Log ".........:" "Cyan"
    Write-Log "........::" "Cyan"
    Write-Log ".......:::" "Cyan"
    Write-Log "......::::" "Cyan"
    Write-Log ".....:::::" "Cyan"
    Write-Log "....::::::" "Cyan"
    Write-Log "...:::::::" "Cyan"
    Write-Log "..::::::::" "Cyan"
    Write-Log ".:::::::::" "Cyan"
    Write-Log "::::::::::" "Cyan"
    Write-Log ":::::::::|" "Cyan"
    Write-Log "::::::::||" "Cyan"
    Write-Log ":::::::|||" "Cyan"
    Write-Log "::::::||||" "Cyan"
    Write-Log ":::::|||||" "Cyan"
    Write-Log "::::||||||" "Cyan"
    Write-Log ":::|||||||" "Cyan"
    Write-Log "::||||||||" "Cyan"
    Write-Log ":|||||||||" "Cyan"
    Write-Log "||||||||||" "Cyan"
    
    if ($Hidden){
        break
    }
    else {
        Write-Log "Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        #$choice = Read-Host "Press any key to exit..."
        break
    }
}

# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# =====================================================================================
# 1. Get drive root letter (исправлено: добавлена проверка на пустоту $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    # Если запущено в консоли без файла, берем текущий диск
    $CleanDriveID = Split-Path -Path $pwd.Path -Qualifier
} else {
    # Извлекаем букву диска (например, "E:") без лишних слэшей
    $CleanDriveID = Split-Path -Path $PSScriptRoot -Qualifier
}

# Гарантируем, что буква диска будет в формате "C:" (без слэша на конце)
$ScriptDriveLetter = $CleanDriveID + "\"

# 2. Get disk information
$DriveInfo = Get-WmiObject -ClassName Win32_LogicalDisk -Filter "DeviceID = '$CleanDriveID'"

# 3. Check if it is NOT a removable drive (DriveType 2)
# Проверяем, удалось ли вообще найти диск, чтобы избежать ошибок
if ($null -eq $DriveInfo) {
    Write-Log "Could not determine drive information." "Error"
} elseif ($DriveInfo.DriveType -ne 2) {
    Write-Log "Script started not from usb drive. Deleting..." "Warning"
    # Remove files
    #Remove-Item -Path (Join-Path $PSScriptRoot "PSChecker.bat") -Force -ErrorAction SilentlyContinue
    #Remove-Item -Path (Join-Path $PSScriptRoot "PSChecker.ps1") -Force -ErrorAction SilentlyContinue
} else {
    Write-Log "Started from USB Flash ($ScriptDriveLetter)." "Good"
}


Write-Log "`n=== Script completed ==="
Stop-Transcript
exit
