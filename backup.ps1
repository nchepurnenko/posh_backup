# Скрипт для резервного копирования v2
# ОКБ Зенит, 2017 v1
# ОКБ Зенит, 2020 v2
# скрипт принимает конфигурационный файл
# формат конфигурационного файла:
# mode > source > destination > log
# mode: 0, 0MIR, 0MIRl, число в формате двух цифр (10, 01, 08)
#   0 - ежедневный накопительный 
#   OMIR - ежедневное зеркало
#   0MIRl - ежедневное зеркало для не NTFS (не копируются права)
#   число  - копирование файлов только за эту дату
# source: полный путь к источнику
# destination: полный путь к папке назначения
# log: полный путь к файлу лога утилиты robocopy, для каждой строки свой лог 
# 13.02.2020 добавлено копирование из теневой копии

#параметры которые принимает скрипт
param ( 
  [string]$confFile = "C:\ut\backup.conf", 
  [string]$logFile = "C:\ut\backup.log",
  [string]$errLog = "C:\ut\err.log",
  [string]$shadowDisk = "Y:"
)

function toLog([string]$text, $file) {
  Out-File -filepath $file -Append -InputObject $text -Encoding utf8
}

# поиск ошибок в файле лога
function parseLog($logFile, $errFile = $errLog) {
  # cписок ошибок robocopy
  $robocopyErrors = "0x00000005", "0x00000006", `
    "0x00000020", "0x00000035" , "0x0000003A", `
    "0x00000040", "0x00000070", "0x00000021";
  $logContent = Get-Content $logFile;
  $logContent | ForEach-Object {
    $str = $_;
    # поиск номера ошибки в каждой строке лога
    $robocopyErrors | ForEach-Object {
      $cmpStr = "*" + $_ + "*";
      if ($str -like $cmpStr) {
        toLog -text $str -file $errFile
      }
    }
  } 
}

# создание теневой копии диска, с которого будет производиться резервное копирование
function createShadowCopy($disk, $shadowDisk) {
  if (-not (Test-Path -path $disk)) {
    $text = "Не найден диск для создания резервной копии"
    toLog -text "$(get-date)$text" -file $logFile
    return
  }

  $shadowTmp = "C:\ut\diskshadow.tmp"
  # delete shadows exposed $shadowDisk
  $shadowText = "
  set context persistent nowriters
  set verbose off
  add volume $disk alias bk
  create
  expose %bk% $shadowDisk"

  $shadowText | Set-Content $shadowTmp
  C:\windows\system32\diskshadow /s $shadowTmp
  Remove-Item $shadowTmp
  if (-not (Test-Path $shadowDisk)) {
    $text = "Невозможно подключить диск с теневой копией"
    toLog -text "$(get-date) $text" -file $logFile
    return
  }
  return
}
# удаление созданной теневой копии
function deleteShadowCopy($shadowDisk) {
  $shadowTmp = "C:\ut\diskshadow.tmp"
  $shadowText = "delete shadows exposed $shadowDisk"
  $shadowText | Set-Content $shadowTmp
  C:\windows\system32\diskshadow /s $shadowTmp
  Remove-Item $shadowTmp
}

# очистка переменной
Remove-Variable -Name robocopyopt -Force -ErrorAction SilentlyContinue
Remove-Variable -Name date -Force -ErrorAction SilentlyContinue

$curD = get-date

#проверяем, что указаны все параметры и доступен файл конфигурации
if ($confFile -and $logfile) {
  if (Test-Path -Path $confFile) {

    #разбираем файл конфигурации
    $Params = Get-Content -LiteralPath $confFile #получение строки из файла
  
    foreach ($param in $params) {
	  if ($param.Chars(0) -eq "#") {
		  continue;
	  }
      $p = $Param.Split(">")
      $mode = $p[0].trim(); 
      $src = $p[1].trim();
      $rec = $p[2].trim();
      $rlog = $p[3].trim();
      $logText = "_________$(get-date)_________"
      toLog -text $logText -file $logFile

      $errorText = "ERROR: копирование $p завершено в c ошибкой`r`n";
      $successText = "SUCCESS: копирование $p успешно завершено`r`n";
      $beginText = "Копирование $p началось`r`n";
      
      # позволяет задать лог-файл для robocopy
      $logOpt = ''
      if ($rlog -ne '') {
        $logOpt = "/unilog:" + $rlog + " /np /ns /nc /fp"
      }
       
      
      $repOpt = " /R:0 /W:0"

      # применение разных опций в зависимости от ситуации
      switch -wildcard ($mode) { 
        "0" { $robocopyopt = "/E /XF *.mp3 " + $logOpt + $repOpt } #каждый день
        "0MIR" { $robocopyopt = "/MIR /COPY:DATS /XF *.mp3 " + $logOpt + $repOpt } #каждый день зеркало Windows
        "0MIRl" { $robocopyopt = "/MIR " + $logOpt + $repOpt } #каждый день зеркало linux
        "[0-9][0-9]" {
          # определенная дата
          $robocopyopt = "/E " + $logOpt + $repOpt; 
          #получение числа месяца в формате даты
          #если это число еще не наступило, то получаем число из прошлого месяца
          #если уже или больше, то число из текущего месяца
          if ($curD.day -lt $mode) {
            $m = ($curD.Month - 1);
          }
          else {
            $m = $curD.Month;    
          }
          $y = $curD.Year;
          $date = (get-date "$mode.$m.$y").Date;  
        }  
        "[0-9][0-9]VM" {
          # выполнение бэкапа виртуальных машин в определенную дату
          # нужен модуль 7zip4powershell
          # Install-Module -Name 7Zip4Powershell -RequiredVersion 1.10.0.0
          if ($curD.day -eq $mode.Substring(0,2))
          {
            toLog -text "$(get-date) $beginText" -file $logFile
            # попытка получить VM на сервере
            $vm = Get-VM $src -ErrorAction SilentlyContinue; 
            if ($null -eq $vm)
            {
              # если ВМ нет на сервере, переход к следующей
              continue;
            } 

            $ExportFolderName = "$($src)$($curD.Day)$($curD.Month)$($curD.Year)";
            $zipName = "$($ExportFolderName).zip"; 

            Export-VM -VM $vm -path $rec\$ExportFolderName;
            
            if (-not (test-path -path $rec\$ExportFolderName))
            {
              $text = "ERROR: Не удалось экспортировать ВМ $src"
              toLog -text "$(get-date) $text" -file $logFile
            }
            Compress-7Zip -path $rec\$ExportFolderName -ArchiveFileName $rec\$zipName -Format Zip -CompressionLevel Fast

            if (-not (test-path -path $rec\$zipName))
            {
              $text = "ERROR: Не удалось создать архив $zipName"
              toLog -text "$(get-date) $text" -file $logFile
            }
            toLog -text "$(get-date) $successText" -file $logFile
            # удаление копий старше 2 месяцев
            Get-ChildItem -Path \\srvbk2\vm$ |`
            Where-Object {$_.LastWriteTime.Month -lt (get-date).addmonths(-1).month} |`
            ForEach-Object {Remove-Item -force $_}
          }
          
        }                 
        default { }
      }
      if ($robocopyopt) {

        if ((Test-Path -path $src) -and (Test-Path -path $rec)) {
          # копирование файлов за определенную дату
          if ($date) {
            toLog -text "$(get-date) $beginText" -file $logFile
            $files = @(Get-ChildItem  $src -Recurse | Where-Object { $_.LastWriteTime.Date -eq $date });
            
            foreach ($file in $files) {
              robocopy $src $rec $file $robocopyopt.Split(' ');
              if ($LASTEXITCODE -gt 7) {
                toLog -text "$(get-date) $errorText" -file $logFile
                parseLog -logFile $rlog
              }
              else {
                toLog -text "$(get-date) $successText" -file $logFile
              }
            }
          }
          else {
            # получаем путь к исходному диску
            $disk = $src.Substring(0, 2)
            if ($disk -ne "\\") {
              # создаем теневую копию и подключаем как диск
              createShadowCopy -disk $disk -shadowDisk $shadowDisk
              if (Test-Path $shadowDisk) {
              $src = $src.Replace($disk, $shadowDisk)
              }
            }
            
            toLog -text "$(get-date) $beginText" -file $logFile
            robocopy $src $rec $robocopyopt.Split(' ')
            deleteShadowCopy -shadowDisk $shadowDisk
            if ($LASTEXITCODE -gt 7) {
              toLog -text "$(get-date) $errorText" -file $logFile
              parseLog -logFile $rlog
            }
            else {
              toLog -text "$(get-date) $successText" -file $logFile
            }
          }
        }
        else {
          $logText = "ERROR: Недоступен источник (" + $src + ") или получатель (" + $rec + ")`r`n"
          toLog -text $logText -file $logFile
        }
      }
      else {
        $logText = "INFO: Нечего копировать или ошибка в файле конфигурации - не указана дата выполнения операции в $p`r`n"
        toLog -text $logText -file $logFile
      }
    }
  }
  else {
    $logText = "ERROR: Файл конфигурации недоступен`r`n"
    toLog -text $logText, -file $logFile
  }
}  
else {
  $logText = "Необходимо указать параметры conffile и logfile`r`n"
  toLog -text $logText -file $logFile
}

