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

$script:hidden = $true

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


# Функция, берущая IP адресс системы
function IpAdressGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting IP adress ===" "Cyan"
        # Обращаемся к конфигу сетевой карты и смотрим какие драйверы вообще включены
        $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Format-List *
    }
    else {
        Write-Log "=== Getting IP adress ===" "Cyan"
        # Обращаемся к конфигу сетевой карты и смотрим какие драйверы вообще включены
        $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'"
        # Print all necessary data as table
        foreach ($adapter in $adapters) {
            Write-Log "Network Adapter : $($adapter.Description)"
            Write-Log "IP Adress(es)   : $($adapter.IPAddress -join ', ')"
            Write-Log "Subnet Mask     : $($adapter.IPSubnet -join ', ')" 
            Write-Log "Default Gateway : $($adapter.DefaultIPGateway -join ', ')"
            Write-Log "MAC Adress      : $($adapter.MACAdress)"
            Write-Log (" ")
        }
    }
}
# Функция, сканирующяа сетевые адаптеры
function NetAdapterGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting data about network adapters ===" "Cyan"
        Get-WmiObject -Class Win32_NetworkAdapter | Format-List *
    }
    else {
        Write-Log "=== Getting data about network adapters ===" "Cyan"
        Get-WmiObject -Class Win32_NetworkAdapter -Filter "PhysicalAdapter = True" |
        ForEach-Object {
            New-Object PSObject -Property @{
                "Name"        = $_.Name
                "DeviceID"    = $_.DeviceID
                "MACAdress"   = $_.MACAdress
                "AdapterType" = $_.AdapterType
                "NetEnabled"  = $_.NetEnabled
            }
        } | Format-List
    }
}

# Функция, берущая данные из BIOS
function BIOSGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting data from BIOS ===" "Cyan"
        Get-WmiObject -Class Win32_BIOS | Select-Object -Property * | Format-List
    }
    else {
        Write-Log "=== Getting data from BIOS ===" "Cyan"
        Get-WmiObject -Class Win32_BIOS | ForEach-Object {
            New-Object PSObject -Property @{
                "ComputerName" = $_.PSComputerName
                "Name"         = $_.Name
                "ReleaseDate"  = $_.ReleaseDate
                "SerialNumber" = $_.SerialNumber
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List
    }
}

# Функция, берущая данные от процессора
function CPUGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting data from CPU ===" "Cyan"
        Get-WmiObject -Class Win32_Processor | Select-Object -Property * | Format-List
    }
    else {
        Write-Log "=== Getting data from CPU ===" "Cyan"
        Get-WmiObject -Class Win32_Processor | ForEach-Object {
            New-Object PSObject -Property @{
                "Name"         = $_.Name
                "ComputerName" = $_.PSComputerName
                "DeviceID"     = $_.DeviceID
                "ProcessorID"  = $_.ProcessorID
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List
    }
}

# Функция, берущая данные из оперативной памяти
function RAMGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting data from RAM ===" "Cyan"
        Get-WmiObject -Class Win32_PhysicalMemory | Select-Object -Property * | Format-List
    }
    else {
        Write-Log "=== Getting data from RAM ===" "Cyan"
        # Calls special data from RAM
        Get-WmiObject -Class Win32_PhysicalMemory | ForEach-Object {
            New-Object PSObject -Property @{
                "Slot"       = $_.DeviceLocator
                "Size(Gb)"   = [math]::round($_.Capacity / 1GB, 1)
                "Frequency"  = $_.Speed
                "Vendor"     = $_.Manufacturer.Trim()
                "PartNumber" = $_.PartNumber
            }
        } | Format-List
    }
}

# Функция, берущая данные от видеокарты
function VRAMGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting data from GPU ===" "Cyan"
        Get-WmiObject -Class Win32_VideoController | Select-Object -Property * | Format-List
    }
    else {
        Write-Log "=== Getting data from GPU ===" "Cyan"
        # Calls some of required data from VideoCard
        Get-WmiObject -Class Win32_VideoController | ForEach-Object {
            New-Object PSObject -Property @{
                "Name"         = $_.Name
                "Memory"       = [math]::round($_.AdapterRAM / 1MB, 0)
                "Driver"       = $_.DriverVersion
                "ProcessorID"  = $_.ProcessorID
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List
    }
}

# Функция, обращающаяся к диску и берущая инфу из него
function DiskGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting data about disks ===" "Cyan"
        Write-Log "Physical disks: " "Warning"
        Get-WmiObject -Class Win32_DiskDrive | Select-Object -Property * | Format-List
        Write-Log "Logical volumes: " "Warning"
        Get-WmiObject -Class Win32_LogicalDisk | Select-Object -Property * | Format-List
    }
    else {
        Write-Log "=== Getting data about disks ===" "Cyan"
        Write-Log "Physical disks: " "Warning"
        # This command calls physical Disk driver
        Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {
            New-Object PSObject -Property @{
                "Name"         = $_.Name
                "Model"        = $_.Model
                "Size (GB)"    = [math]::round($_.Size / 1GB, 1)
                "Type"         = $_.InterfaceType
                "PartNumber"   = $_.PartNumber
                "Manufacturer" = $_.Manufacturer

            }
        } | Format-List

        Write-Log "Logical volumes: " "Warning"
        # This command calls logical Disks
        Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 3" | ForEach-Object {
            New-Object PSObject -Property @{
                "Disk"         = $_.DeviceID
                "Size (GB)"    = [math]::round($_.Size / 1GB, 1)
                "Free (GB)"    = [math]::round($_.FreeSpace / 1GB, 1)
                "FileSystem"   = $_.FileSystem
                "PartNumber"   = $_.PartNumber
                "Manufacturer" = $_.Manufacturer
            }
        } | Format-List
    }
}

function MonitorGet {
    param (
        [switch]$On
    )
    if ($On) {
        Write-Log "=== Getting data about monitor ===" "Cyan"
        Get-WmiObject -Namespace "root\wmi" -Class "WmiMonitorID"
    }
    else {
        Write-Log "=== Getting data about monitor ===" "Cyan"
        $Monitors = Get-WmiObject -Namespace "root\wmi" -Class "WmiMonitorID"

        foreach ($Monitor in $Monitors) {
            $Namebytes = $Monitor.UserFriendlyName | Where-Object { $_ -ne 0 }
            $MonitorName = if ($Namebytes) { [System.Text.Encoding]::ASCII.GetString($Namebytes) } else { "Unknown" }

            $Serialbytes = $Monitor.SerialNumberID | Where-Object { $_ -ne 0 }
            $SerialNumber = if ($SerialBytes) { [System.Text.Encoding]::ASCII.GetString($SerialBytes) } else { "Unknown" }
                
            New-Object PSObject -Property @{
                "Model"    = $MonitorName
                "Serial N" = $SerialNumber
                "Part ID"  = $Monitor.InstanceName
            } | Format-List
        }
    }
}

function PeripheralGet {
    param (
        [switch]$On
    )
    $Classes = @{
        "Keyboard" = "Keyboard"
        "Mouse"    = "Mouse"
        "AUDIO"    = "Volume"
        "Printer"  = "PNPPrinters"
    }
    foreach ($Target in $Classes.Keys) {
        Write-Log "[$Target]:" 
        $Devices = Get-PnpDevice -Class $Classes[$Target] -Status OK -ErrorAction SilentlyContinue
        if ($Devices) {
            $Devices | Format-Table FriendlyName, InstanceId -AutoSize
        }
        else {
            Write-Log "  Подключенные устройства не найдены" -ForegroundColor Gray
        }
    }   

    # 3. ПОЛУЧЕНИЕ ДАННЫХ О ФЛЕШКАХ И СЪЕМНЫХ НОСИТЕЛЯХ
    Write-Log "`n=== REMOVABLE DISKS ===" "Cyan"
    # Вариант 1: Логические диски (буква, файловая система, объем)
    Write-Log "Logical USB-disks" 
    $UsbDrives = Get-WmiObject -Class Win32_Volume | Where-Object { $_.DriveType -eq 2 } # 2 = Съемный диск
    if ($UsbDrives) {
        $logical = foreach ($Drive in $UsbDrives) {
            New-Object PSObject -Property @{
                "Disk letter" = $Drive.DriveLetter
                "Tome"        = $Drive.Label
                "Filesystem"  = $Drive.FileSystem
                "Free (GB)"   = [Math]::Round($Drive.FreeSpace / 1GB, 2)
                "All (GB)"    = [Math]::Round($Drive.Capacity / 1GB, 2)
            } 
        }
        $Logical | Format-Table -AutoSize | Out-Host
    }
    else {
        Write-Log "Active flash volumes not found" -ForegroundColor Gray
    }

    # Вариант 2 - Физические USB-накопители
    Write-Log "Physical USB-Drives" "Warning"
    $UsbDiskDrives = Get-WmiObject -Class Win32_DiskDrive | Where-Object { $_.InterfaceType -eq "USB" }
    if ($UsbDiskDrives) {
        $UsbDiskDrives | Format-Table Model, Size, DeviceID -AutoSize
    }
    else {
        Write-Host "Physical USB-Disks not found" -ForegroundColor Gray
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
    $Programs = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName }
    $Result = @()
    foreach ($Program in $Programs) {
        $Name = $Program.DisplayName
        $Raw =$Program.InstallDate
        $CleanDate = $Raw
        
        if ($RawDate -and $RawDate -match '^\d{8}$') {
            try {
                $CleanDate = [datetime]::ParseExact(
                    $RawDate, 
                    'yyyyMMdd', 
                    $null
                ).ToString('dd.MM.yyyy')
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
        # Format output data as table 
        $Result += New-Object PSObject -Property @{
            "Program"           = $Name
            "Version"           = $Program.DisplayVersion
            "Installation Date" = $FinalDate
            "Update Date"       = $CleanDate
            "Manufacturer"      = $Program.Publisher
        } 
    }
    $Result | Format-Table -AutoSize | Out-String -Width 4096
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
    Write-Log "Seeking for ViPNeT in product list"
    Get-WmiObject -Class Win32_Product |
    Where-Object { $_.Name -match 'ViPNet|Infotecs' } |
    Select-Object Name, Version, Vendor, InstallDate, InstallLocation | Format-List

    # Seek in registry
    Write-Log "Seeking for ViPNeT in registry"
    Get-ItemProperty `
        HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
        HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, `
        HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName -match 'ViPNet|Infotecs' } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate,
    InstallLocation, UninstallString, QuietUninstallString | Format-List
            
    # Seek in file system
    $Roots = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:ProgramData",
        "$env:LOCALAPPDATA",
        "$env:APPDATA"
    ) | Where-Object { $_ -and (Test-Path $_) }

    Get-ChildItem $Roots -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'ViPNet|Infotecs' } |
    Select-Object FullName, CreationTime, LastWriteTime | Format-List

    # Seek ViPNeT in processes
    Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'ViPNet|Infotecs|Coordinator|Monitor|Client' } |
    Select-Object Name, Id, Path, Company, ProductVersion, StartTime | Format-List

    # Seek ViPNeT in services (в службах)
    Get-WmiObject -Class Win32_Service |
    Where-Object { $_.Name -match 'ViPNet|Infotecs' -or $_.DisplayName -match 'ViPNet|Infotecs' } |
    Select-Object Name, DisplayName, State, StartMode, StartName, PathName | Format-List

    # Seek ViPNeT at startup commands (поиск в автозапуске)
    Get-WmiObject -Class Win32_StartupCommand |
    Where-Object { $_.Name -match 'ViPNet|Infotecs' -or $_.Command -match 'ViPNet|Infotecs' } |
    Select-Object Name, Command, Location, User | Format-List
    # Seek ViPNeT in TCP connections
    # 1. Собираем ID всех процессов, чьи имена содержат нужные ключевые слова
    $ProcessIds = Get-Process -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match 'ViPNet|Infotecs|Coordinator|Monitor|Client' } | 
    Select-Object -ExpandProperty Id

    # Проверяем, нашли ли мы процессы, чтобы не запускать netstat вхолостую
    if ($ProcessIds) {
        # 2. Вызываем netstat -ano (флаг -o выводит PID в конце каждой строки)
        netstat -ano | ForEach-Object {
            $Line = $_.Trim()
            # Регулярным выражением забираем PID (это цифры в самом конце строки)
            if ($Line -match '(?<PID>\d+)$') {
                $PidFound = [int]$Matches['PID']
                # 3. Эквивалент оператора -in для PowerShell 2.0: проверяем, содержит ли массив $ProcessIds этот PID
                if ($ProcessIds -contains $PidFound) {
                    # Разбираем строку netstat на понятные свойства и выводим объектом
                    $Parts = $Line -split '\s+'
                    New-Object PSObject -Property @{
                        "Protocol"       = $Parts[0]
                        "LocalAddress"   = $Parts[1]
                        "ForeignAddress" = $Parts[2]
                        "State"          = if ($Parts[0] -eq 'UDP') { "N/A" } else { $Parts[3] }
                        "OwningProcess"  = $PidFound
                    }
                }
            }
        } | Format-List
    }
    # 1. Запрашиваем абсолютно все правила брандмауэра через netsh
    # Утилита сама вернет текст на языке локализации ОС (русском или английском)
    $RulesText = netsh advfirewall firewall show rule name=all verbose

    # Разделяем весь вывод на отдельные блоки (правила разделены строками из дефисов "---")
    $RuleBlocks = $RulesText -split '-{5,}'

    foreach ($Block in $RuleBlocks) {
        # 2. Фильтруем правила по ключевым словам 'ViPNet' или 'Infotecs'
        if ($Block -match 'ViPNet|Infotecs') {
                    
            # 3. Собираем данные из текстового блока с помощью регулярных выражений
            # Конструкция учитывает как английские, так и русские имена полей netsh
            $Name = if ($Block -match '(?:Rule Name|Имя правила):\s*(.*)') { $Matches[1].Trim() }
            $Protocol = if ($Block -match '(?:Protocol|Протокол):\s*(.*)') { $Matches[1].Trim() }
            $LocalPort = if ($Block -match '(?:LocalPort|Локальный порт):\s*(.*)') { $Matches[1].Trim() }
            $RemotePort = if ($Block -match '(?:RemotePort|Удаленный порт):\s*(.*)') { $Matches[1].Trim() }
            $Action = if ($Block -match '(?:Action|Действие):\s*(.*)') { $Matches[1].Trim() }

            # Выводим информацию в виде аккуратного объекта для Format-List
            if ($Name) {
                New-Object PSObject -Property @{
                    "DisplayName" = $Name
                    "Protocol"    = $Protocol
                    "LocalPort"   = $LocalPort
                    "RemotePort"  = $RemotePort
                    "Action"      = $Action
                }
            }
        }
    } 

    Get-ChildItem Cert:\LocalMachine\My, Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Subject -match 'ViPNet|Infotecs' -or
        $_.Issuer -match 'ViPNet|Infotecs' -or
        $_.EnhancedKeyUsageList.FriendlyName -match 'ViPNet|Infotecs'
    } |
    Select-Object PSParentPath, Subject, Issuer, Thumbprint,
    NotBefore, NotAfter, HasPrivateKey, SerialNumber | Format-List

    certutil -csplist
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

# Корректный поиск флешки через стабильный Win32_LogicalDisk
$UsbDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 2" | Select-Object -First 1

if ($UsbDrive -and $UsbDrive.DeviceID) {
    # .DeviceID вернет букву диска с двоеточием, например "E:"
    $LogPath = Join-Path -Path $PSScriptRoot -ChildPath "$ComputerName`_scanner_log.txt"
    #$LogPath = "$($UsbDrive.DeviceID)\$ComputerName`_scanner_log.txt"
}
else {
    # Если флешка не вставлена, пишем лог на рабочий стол
    $LogPath = "$home\Desktop\$ComputerName`scanner_log.txt"
}

# Включаем запись ВСЕГО терминала в файл
Start-Transcript -Path $LogPath -Append -Force

if ($Host.UI.RawUI) {
    $Size = $Host.UI.RawUI.BufferSize; $Size.Width = 4000; $Host.UI.RawUI.BufferSize = $Size
}

Write-Log "=== RUN SCANNER ON PC: $ComputerName ===" "Cyan"
if (-not $UsbDrive) { 
    Write-Log "ATTENTION: USB Flash not found, writing log on Desktop!" "Error" 
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







# Запускаем проверщик винды и офиса.
WindowsOfficeCheck
# Берём IP-адресс устройства
IpAdressGet 
# Берём инфу с сетевой карты
NetAdapterGet
# Берём инфу с процессора
CPUGet
# Берём инфу с видеокарты
VRAMGet
# Берём инфу с оперативной памяти
RAMGet 
# Берём инфу с дисков
DiskGet
# Обращаемся к Биосу чтобы вывести информацию о нем и о системе
BIOSGet
# Сканируем на наличие мониторов
MonitorGet
# Получаем всю инфу о подключённой периферии
PeripheralGet

Write-Log "Check does deep inspection is required..."
while ($true) {
    $choice = "y"
    #$choice = Read-Host "You wanna get more data about PC? (y/n)..."
    if ($choice -eq 'y') {
        # The same one but without choosing what it have to print
        IpAdressGet -On
        NetAdapterGet -On
        CPUGet -On
        VRAMGet -On
        RAMGet -On
        DiskGet -On
        BIOSGet -On
        MonitorGet -On
        PeripheralGet -On
        break
    }
    break
}

#Запускаем поисковик программ
Write-Log "Seeker mode"
while ($true) {
    $choice = 'y'
    #$choice = Read-Host "We will scan PC on programs? (y/n)"
    if ($choice -eq 'y') {
        Write-Log "Scanning all programs..." "Cyan"
        SeekObjects
        Write-Log "Scanning for ViPNeT..." "Cyan"
        ViPNeTSeek
        break
    }
    break
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
    Write-Log ":::::::::⠿" "Cyan"
    Write-Log "::::::::⠿⠿" "Cyan"
    Write-Log ":::::::⠿⠿⠿" "Cyan"
    Write-Log "::::::⠿⠿⠿⠿" "Cyan"
    Write-Log ":::::⠿⠿⠿⠿⠿" "Cyan"
    Write-Log "::::⠿⠿⠿⠿⠿⠿" "Cyan"
    Write-Log ":::⠿⠿⠿⠿⠿⠿⠿" "Cyan"
    Write-Log "::⠿⠿⠿⠿⠿⠿⠿⠿" "Cyan"
    Write-Log ":⠿⠿⠿⠿⠿⠿⠿⠿⠿" "Cyan"
    Write-Log "⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿" "Cyan"
    Write-Log "⠿⠿⠿⠿⠿⠿⠿⠿⠿⣿" "Cyan"
    Write-Log "⠿⠿⠿⠿⠿⠿⠿⠿⣿⣿" "Cyan"
    Write-Log "⠿⠿⠿⠿⠿⠿⠿⣿⣿⣿" "Cyan"
    Write-Log "⠿⠿⠿⠿⠿⠿⣿⣿⣿⣿" "Cyan"
    Write-Log "⠿⠿⠿⠿⠿⣿⣿⣿⣿⣿" "Cyan"
    Write-Log "⠿⠿⠿⠿⣿⣿⣿⣿⣿⣿" "Cyan"
    Write-Log "⠿⠿⠿⣿⣿⣿⣿⣿⣿⣿" "Cyan"
    Write-Log "⠿⠿⣿⣿⣿⣿⣿⣿⣿⣿" "Cyan"
    Write-Log "⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿" "Cyan"
    Write-Log "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿" "Cyan"
    
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
# 1. Get drive root letter
$ScriptDriveLetter = [System.IO.Path]::GetPathRoot($PSScriptRoot)
$CleanDriveID = $ScriptDriveLetter.Trim("\")

# 2. Get disk information
$DriveInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID = '$CleanDriveID'"

# 3. Check if it is NOT a removable drive (DriveType 2)
if ($DriveInfo.DriveType -ne 2) {
    Write-Log "Script started not from usb drive. Deleting..." "Warning"
    
    # Remove files
    #Remove-Item -Path (Join-Path $PSScriptRoot "PSChecker.bat") -Force -ErrorAction SilentlyContinue
    #Remove-Item -Path (Join-Path $PSScriptRoot "PSChecker.ps1") -Force -ErrorAction SilentlyContinue
}
else {
    Write-Log "Started from USB Flash ($ScriptDriveLetter)." "Good"
}

Write-Log "`n=== Script completed ==="
Stop-Transcript
exit
