if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    # Если нет, перезапускаем скрипт с правами администратора
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "powershell";
    $newProcess.Arguments = "& '" + $myInvocation.MyCommand.Definition + "'";
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit;
}

$StartPort = "29"
$ServiceName = "1C:Enterprise 8.3 Server Agent (x86-64) $($StartPort)41"
$PlatformPath = "C:\Program Files\1cv8\8.3.24.1667"

$Path = """$PlatformPath\bin\ragent.exe"""
$ServiceInfo = """C:\Program Files\1cv8\srvinfo$($StartPort)41"""
$ServiceInfoForClean = "C:\Program Files\1cv8\srvinfo$($StartPort)41"
$ServiceDisplayName = "Агент сервера 1С:Предприятия 8.3 (x86-64) $($StartPort)41"
$BinaryPath = "$Path -srvc -agent -regport $($StartPort)41 -port $($StartPort)40 -range $($StartPort)60:$($StartPort)91 -d $ServiceInfo -debug"
$Creds = Get-Credential

$CtrlPort = "$($StartPort)40"
$AgentName = [System.Net.Dns]::GetHostByName($env:computerName) | Select-Object -ExpandProperty hostname
$RASPort = "$($StartPort)45"
$RASPath = """$PlatformPath\bin\ras.exe"""
$SrvcName = "1C:Enterprise 8.3 Remote Server $($StartPort)45"
$BinPath = "$RASPath cluster --service --port=$RASPort $AgentName`:$CtrlPort"
$Description = "1C:Enterprise 8.3 Remote Server $($StartPort)45"

# Создание новой службы
New-Service -Name $SrvcName -BinaryPathName $BinPath -DisplayName $Description -StartupType Automatic

# Запуск службы
Start-Service -Name $SrvcName

New-Service -Name $ServiceName -BinaryPathName $BinaryPath -DisplayName $ServiceDisplayName -StartupType Automatic -Credential $Creds
Start-Service -Name $ServiceName
Stop-Service -Name $ServiceName
Stop-Service -Name $SrvcName
foreach($process in (Get-WmiObject win32_process | Where-Object {($_.Name -eq 'rphost.exe' -or $_.Name -eq 'rmngr.exe') -and $_.CommandLine -like "$($StartPort)91*"}))
{
    Stop-Process $process
}


Start-Sleep -Seconds 30


$reg_info = Get-ChildItem -Path ($ServiceInfo -replace '"','') -Force | Select-Object -ExpandProperty Fullname

$lst_files = Get-ChildItem -Path $reg_info -Force -Recurse -Filter "*.lst" | Select-Object -ExpandProperty Fullname

# Получаем текущее время в формате yyyyMMdd_HHmmss
$currentTime = Get-Date -Format "yyyyMMdd_HHmmss"

# Копируем каждый файл с добавлением расширения .lst_old{момент времени}
foreach ($file in $lst_files) {
    $folderPath = [System.IO.Path]::GetDirectoryName($file)
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $fileExtension = [System.IO.Path]::GetExtension($file)
    $newFileName = $fileName + $currentTime  + ".lst_old"
    $newFilePath = Join-Path -Path $folderPath -ChildPath $newFileName
    Copy-Item -Path $file -Destination $newFilePath
}


$ComputerName = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Name
$FQDN = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Name) + "." + (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain)

if ((Get-WmiObject win32_service | Where-Object {$_.Name -eq $ServiceName} | Select-Object -ExpandProperty State) -eq "Stopped")
{
    foreach ($lst_file in $lst_files) {
        if (Test-Path $lst_file) {
            $content = Get-Content -Path $lst_file -Raw
            if (-not (Select-String -InputObject $content -Pattern $FQDN)) {
                $newContent = $content -replace [regex]::Escape($ComputerName), $FQDN
                Set-Content -Path $lst_file -Encoding UTF8 -Value $newContent
            }
        }
    }  
}
Start-Service -Name $ServiceName
Start-Service -Name $SrvcName
