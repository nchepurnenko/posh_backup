# зенит, 2020 
# Установка скрипта бэкапа на сервере 
# создание папок, копирование файлов, добавление задания в шедулер

param (
    [string]$Distr = "\\srvbk2\ut",
    [string]$installPath = "C:\ut",
    [string]$execTime = "07:00PM",
    # [string]$user = "zenith\backup"
    [string]$user = "NT AUTHORITY\SYSTEM"
)

if ($Distr -eq "") {
    Write-Host "Не указан путь к дистрибутиву. По умолчанию \\srvbk2\ut"
    return
}
if ($installPath -eq "") {
    Write-Host "Не указана папка установки. По умолчанию C:\ut"
    return
}

# Создать папку если ее нет
if (!(Test-Path -Path $installPath)) {
    New-item -Path $installPath -ItemType Directory   
    $sid = 'S-1-5-32-544'
    $user = (New-Object System.Security.Principal.SecurityIdentifier ($sid)).Translate( [System.Security.Principal.NTAccount]).Value
    New-SmbShare -Name "ut$" -Path $installPath  -FullAccess $user -ReadAccess "zenith\a-K29AdminsBackup" 
} 

#назначение разрешений для папки
$dirAcl = Get-Acl -Path $installPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule `
    "zenith\a-k29AdminsBackup", "Read,Write,Modify", "ContainerInherit,ObjectInherit", "none", "allow"
$dirAcl.AddAccessRule($rule)
Set-Acl -Path $installPath -AclObject $dirAcl

#копирование необходимых файлов
# if (Test-Path -Path $Distr) {
#     Copy-Item -Force -Path $Distr\startBackup.ps1 -Destination $installPath
# }

#создание файла лога и конфигурации
if (!(Test-Path -Path $installPath\backup.conf)) {
    New-item -Path $installPath\backup.conf -ItemType File
}
if (!(Test-Path -Path $installPath\backup.log)) {
    New-item -Path $installPath\backup.log -ItemType File
}

# добавление задания в планировщик
$taskPath = "\Zenith\"
$taskName = "backup"
if (Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath
}
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek 1, 2, 3, 4, 5 -At $execTime

# получение пароля пользователя от которого будет запускаться задание
# Write-Host "Enter password for user $user"
# $SecurePassword = $password = Read-Host -AsSecureString
# $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $user, $SecurePassword
# $Password = $Credentials.GetNetworkCredential().Password 

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-noProfile -ExecutionPolicy ByPass -file \\srvbk2\ut\backup.ps1 -conffile C:\ut\backup.conf -logfile C:\ut\backup.log"
Register-ScheduledTask -TaskName $taskName -TaskPath  $taskPath -Trigger $trigger `
    -Action $action -RunLevel Highest -User $user #-Password $password  



