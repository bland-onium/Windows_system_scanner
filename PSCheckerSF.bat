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
        [int]$ThrottleLimit = [Environment]::ProcessorCount
    )

    $Pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
    $Pool.Open()

    # КЛЮЧЕВОЕ: сортируем по весу убыванию ТОЛЬКО для постановки в очередь пула
    $LaunchOrder = $Tasks | Sort-Object LaunchWeight -Descending

    $Jobs = @()
    foreach ($Task in $LaunchOrder) {
        # В скриптблок уходит OutputIndex, а не LaunchWeight и не позиция в очереди
        $PS = [powershell]::Create().AddScript($Task.Block).AddArgument($Task.OutputIndex)
        $PS.RunspacePool = $Pool
        $Jobs += [PSCustomObject]@{
            OutputIndex = $Task.OutputIndex
            Name        = $Task.Name
            PS          = $PS
            Handle      = $PS.BeginInvoke()
        }
    }

    $Results = foreach ($Job in $Jobs) {
        try {
            $Out = $Job.PS.EndInvoke($Job.Handle)
            if ($Out) { $Out }
        }
        catch {
            [PSCustomObject]@{
                Index    = $Job.OutputIndex
                Messages = @(@{ Message = "ERROR in $($Job.Name): $_"; EntryType = "Error" })
            }
        }
        finally {
            $Job.PS.Dispose()
        }
    }

    $Pool.Close()
    $Pool.Dispose()

    # Финальная сортировка по OutputIndex — порядок вывода как в исходнике
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
    Write-Host "`n "
    Write-Log "=== SYSTEM SCANNER STARTINIG ===" "Cyan"
    
    # Теперь запускаем алгоритм массового сканирования реестра на присутствие программ
    $RegPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    # It calls all the objects which has any name
    $Programs = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
    
    # Запрашиваем данные через Get-WmiObject (C(i)mInstance НЕ используется согласно ТЗ)
    # Это позволит вытащить IdentifyingNumber (серийный ID продукта MSI)
    $WmiProducts = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue

    $Result = New-Object System.Collections.ArrayList

    foreach ($Program in $Programs) {
        $Name = $Program.DisplayName
        $RawDate = $Program.InstallDate
        $CleanDate = $RawDate

        if ($RawDate -and $RawDate -match '^\d{8}$') {
            try {
                $CleanDate = [datetime]::ParseExact($RawDate, 'yyyyMMdd', $null).ToString('dd.MM.yyyy')
            } catch {
                $CleanDate = $RawDate
            }
        }

        # We'll seek date of first installation by installation directory
        $FinalDate = "Unknown"
        $InstallDir = $Program.InstallLocation
        if ($InstallDir) {
            $FolderInfo = Get-Item -Path $InstallDir -ErrorAction SilentlyContinue
            if ($FolderInfo) {
                $FinalDate = $FolderInfo.CreationTime.ToString('dd.MM.yyyy')
            }
        }

        # Поиск серийного номера / идентификатора продукта
        # 1. Проверяем реестровый DigitalProductId или SerialNumber (если вендор их туда записал)
        $SerialNumber = "Unknown"
        if ($Program.DigitalProductId) { $SerialNumber = "Has Digital ID" }
        elseif ($Program.SerialNumber) { $SerialNumber = $Program.SerialNumber }
        elseif ($Program.ProductID) { $SerialNumber = $Program.ProductID }
        
        # 2. Если в реестре пусто, ищем совпадение по имени в Get-WmiObject
        if ($SerialNumber -eq "Unknown" -and $WmiProducts) {
            $WmiMatch = $WmiProducts | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
            if ($WmiMatch -and $WmiMatch.IdentifyingNumber) {
                $SerialNumber = $WmiMatch.IdentifyingNumber
            }
        }

        # Format output data as table
        $Result += New-Object PSObject -Property @{
            "Program"           = $Name
            "Version"           = $Program.DisplayVersion
            "Installation Date" = $FinalDate
            "Update Date"       = $CleanDate
            "Manufacturer"      = $Program.Publisher
            "Serial / ProdID"   = $SerialNumber
        }
    }

    $Result | Format-Table -Property "Program", "Version", "Manufacturer", "Installation Date", "Update Date", "Serial / ProdID" -AutoSize | Out-String -Width 4096
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
    Write-Log "=== START ALGORITHM OF CHECKING OFFICE AND WINDOWS ===" "Cyan"
    Write-Log "=== Checking Windows activation ==="
    $License = Get-WindowsLicense

    if ($null -ne $License -and $License.LicenseStatus -eq 1) {
        Write-Log "[GOOD] Windows is already activated (Status: Licensed)" "Good"
    }
    else {
        Write-Log "[BAD] Windows is NOT activated." "Error"
    }

    Write-Log "Windows version"
    Get-WmiObject -Class Win32_OperatingSystem | Select Caption, Version, BuildNmber | Format-List
    Write-log "Office version"
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object {$_.DisplayName -like "*Office*"} | Select-Object DisplayName, DisplayVersion | Format-List


    # --- Office Activation Check ---
    Write-Log "`n=== Checking Office Licenses ===" "Warning"

    $OfficeLicense = Get-WmiObject -Class SoftwareLicensingProduct `
        -Filter "Name LIKE '%Office%' AND LicenseStatus = 1 AND PartialProductKey IS NOT NULL" |
        Where-Object { $_.Name -like "*Office*" } |
        Select-Object -First 1

    if ($OfficeLicense) {
        Write-Log "[GOOD] Office is activated (Licensed)" "Good"
        Write-Log "License: $OfficeLicense"
    }
    else {
        Write-Log "[BAD] Office is NOT activated." "Error"
    }
}

function ViPNeTSeek {
    Write-Log "=== VIPNET SEEKING MODULE STARTED" "Cyan"
    # Lets check for vipnet at common programms
    
    $Pattern = 'ViPNet|Infotecs|Crypto-Pro|Security-Lab'
    $ProcessPattern = 'ViPNet|Infotecs|Coordinator|CryptoPRO|Crypto-Pro'
    
    # Seek in registry
    Write-Log "Seeking for ViPNeT in registry"
    $UninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($Path in $UninstallPaths) {
        Get-ItemProperty $Path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                $_.DisplayName -match $Pattern
            } |
            Select-Object DisplayName,
                DisplayVersion,
                Publisher,
                InstallDate,
                InstallLocation,
                UninstallString,
                QuietUninstallString |
            Format-List
    }

    # Seek ViPNeT in services (в службах)
    Write-Log "Seeking for ViPNet in services"
    
    Get-WmiObject Win32_Service `
        -Filter "Name LIKE '%ViPNet%' OR Name LIKE '%Infotecs%' OR DisplayName '%ViPNet%' OR DisplayName LIKE '%Infotecs%'" `
        -ErrorAction SilentlyContinue |
        Select-Object Name,
                     DisplayName,
                     State,
                     StartMode,
                     StartName,
                     PathName |
        Format-List

    # Seek ViPNeT in processes
    Write-Log "Seeking for ViPNet in processes"

    $VipnetProc = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { 
                $_.Name -match $ProcessPattern
            } 
    )
    if ($VipnetProcesses.Count -gt 0) {
        $VipnetProcesses |
            Select-Object Name,
                          Id,
                          Path,
                          Company,
                          ProductVersion,
                          StartTime |
            Format-List
    }

    # Network
    if ($VipnetProcesses.Count -gt 0) {
        Write-Log "Seeking for ViPNet TCP/UDP connections"
        # Hashtable значительно быстрее, чем
        # $ProcessIds -contains $Pid при большом количестве соединений.
        $ProcessIdMap = @{}
        foreach ($Process in $VipnetProcesses) {
            $ProcessIdMap[[int]$Process.Id] = $true
        }
        netstat -ano 2>$null |
            ForEach-Object {
                $Line = $_.Trim()
                if ($Line -match '^(TCP|UDP)\s+(\S+)\s+(\S+)(?:\s+(\S+))?\s+(\d+)$') {
                    $Protocol       = $Matches[1]
                    $LocalAddress   = $Matches[2]
                    $ForeignAddress = $Matches[3]
                    $State          = $Matches[4]
                    $PidFound       = [int]$Matches[5]
                    if ($ProcessIdMap.ContainsKey($PidFound)) {
                        New-Object PSObject -Property @{
                            Protocol       = $Protocol
                            LocalAddress   = $LocalAddress
                            ForeignAddress = $ForeignAddress
                            State          = if ($Protocol -eq 'UDP') {
                                'N/A'
                            }
                            else {
                                $State
                            }
                            OwningProcess  = $PidFound
                        }
                    }
                }
            } |
            Format-List
    }

    # Seek in file system
    Write-Log "Seeking for ViPNet in file system"
    $MaxDepth = 2
    $Roots = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:ProgramData",
        "$env:LOCALAPPDATA",
        "$env:APPDATA"
    ) | Where-Object { $_ -and (Test-Path $_) }
    $Roots = $Roots | Where-Object {
        $_ -and (Test-Path $_ -ErrorAction SilentlyContinue)
    } | Select-Object -Unique

    $PercentInt = 0
    $TotalRoots = $Roots.Count

    foreach ($Root in $Roots) {
        Get-ChildItem $Root `
            -Directory `
            -Recurse `
            -Depth $MaxDepth `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match $Pattern
            } |
            Select-Object FullName,
                          CreationTime,
                          LastWriteTime |
            Format-List
        $Percent = [math]::Round(($PercentInt / $TotalRoots) * 100)
        $PercentInt++
        Write-Host "Scanning status: $Percent"
    }

    # Firewall scan
    Write-Log "Seeking for ViPNet in firewall rules"
    $RuleTect = netsh advfirewall firewall show rule name=all 2>$null
    $CurrentRule = $null

    foreach ($Line in $RuleText) {
        if ($Line -match '^(Rule Name|Имя правила)\s*:\s*(.+$') {
            $CurrentRule = $Matches[2].Trim()
            if ($CurrentRule -match $Pattern) {
                New-Object PSObject -Property @{
                    DisplayName = $CurrentRule
                }
            }
        }
    } 

    # Certificates
    Write-Log "Seeking for ViPNet certificates"

    $CertificateStores = @(
        'Cert:\LocalMachine\My',
        'Cert:\CurrentUser\My'
    )

    foreach ($Store in $CertificateStores) {

        Get-ChildItem $Store -ErrorAction SilentlyContinue |
            Where-Object {

                ($_.Subject -and $_.Subject -match $Pattern) -or
                ($_.Issuer -and $_.Issuer -match $Pattern) -or
                ($_.EnhancedKeyUsageList -and
                    $_.EnhancedKeyUsageList.FriendlyName -match $Pattern)

            } |
            Select-Object PSParentPath,
                          Subject,
                          Issuer,
                          Thumbprint,
                          NotBefore,
                          NotAfter,
                          HasPrivateKey,
                          SerialNumber |
            Format-List
    }

    # Crypto providers
    Write-Log "Seeking for ViPNet cryptographic providers"
    certutil -csplist 2>$null
    Write-Log "=== VIPNET SEEKING MODULE FINISHED" "Cyan"
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






# Определение задач по порядку вывода
# OutputIndex — порядок вывода
# LaunchWeight — приоритет запуска (тяжёлые раньше)
$TaskBlocks = @(
    [PSCustomObject]@{ Name='WindowsOfficeCheck'; LaunchWeight=30;  OutputIndex=0;  Block={ param($o) WindowsOfficeCheck -OutputIndex $o } }
    [PSCustomObject]@{ Name='IpAdressGet';        LaunchWeight=5;   OutputIndex=1;  Block={ param($o) IpAdressGet        -OutputIndex $o } }
    [PSCustomObject]@{ Name='NetAdapterGet';      LaunchWeight=5;   OutputIndex=2;  Block={ param($o) NetAdapterGet      -OutputIndex $o } }
    [PSCustomObject]@{ Name='CPUGet';             LaunchWeight=10;  OutputIndex=3;  Block={ param($o) CPUGet             -OutputIndex $o } }
    [PSCustomObject]@{ Name='VRAMGet';            LaunchWeight=10;  OutputIndex=4;  Block={ param($o) VRAMGet            -OutputIndex $o } }
    [PSCustomObject]@{ Name='RAMGet';             LaunchWeight=10;  OutputIndex=5;  Block={ param($o) RAMGet             -OutputIndex $o } }
    [PSCustomObject]@{ Name='DiskGet';            LaunchWeight=70;  OutputIndex=6;  Block={ param($o) DiskGet            -OutputIndex $o } }
    [PSCustomObject]@{ Name='BIOSGet';            LaunchWeight=90;  OutputIndex=7;  Block={ param($o) BIOSGet            -OutputIndex $o } }  # тяжёлый
    [PSCustomObject]@{ Name='MonitorGet';         LaunchWeight=15;  OutputIndex=8;  Block={ param($o) MonitorGet         -OutputIndex $o } }
    [PSCustomObject]@{ Name='PeripheralGet';      LaunchWeight=40;  OutputIndex=9;  Block={ param($o) PeripheralGet      -OutputIndex $o } }
    [PSCustomObject]@{ Name='SeekObjects';        LaunchWeight=100; OutputIndex=10; Block={ param($o) SeekObjects        -OutputIndex $o } }  # самый тяжёлый
    [PSCustomObject]@{ Name='ViPNeTSeek';         LaunchWeight=95;  OutputIndex=11; Block={ param($o) ViPNeTSeek         -OutputIndex $o } }  # тяжёлый
)

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
