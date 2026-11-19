#Requires -Version 5.1
param(
  [ValidateSet('Pet','Safe','GPU')][string]$Mode='Pet',
  [switch]$Restart,
  [switch]$SelfTest
)
$ErrorActionPreference='Stop'
$HomeDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$CoreZip=Join-Path $HomeDir 'PET_Core.zip'
$CoreHash='0897fad89cd7d2f3fedcaeed5944616be6309210f9a57d44417290d864a412bd'
$AppBase=Join-Path $env:LOCALAPPDATA 'ComfyUI_PET_Compact'
$AppDir=Join-Path $AppBase 'app'
$Stamp=Join-Path $AppBase 'installed-core.sha256'
$ElectronVersion='45.2.1'
$ElectronZip="electron-v$ElectronVersion-win32-x64.zip"
$ElectronHash='7c342aee45d5b4ccafe5dfe9037028796b082735a576e21e2b4e2d8422ebb727'
$RuntimeRoot=Join-Path $env:LOCALAPPDATA 'ComfyUI_Pet_Runtime'
$RuntimeDir=Join-Path $RuntimeRoot "Electron-$ElectronVersion"
$Exe=Join-Path $RuntimeDir 'electron.exe'
$Log=Join-Path $env:TEMP 'ComfyUI_Pet_Start.log'
function Report([string]$Message) {
  Write-Host $Message
  try {Add-Content -LiteralPath $Log -Value ("["+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+"] "+$Message) -Encoding UTF8} catch {}
}
function VerifyCore {
  if(!(Test-Path -LiteralPath $CoreZip -PathType Leaf)) {throw 'PET_Core.zip is missing. Extract the FULL package.'}
  $actual=(Get-FileHash -LiteralPath $CoreZip -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -ne $CoreHash){throw ('PET_Core.zip failed SHA256 verification: '+$actual)}
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[System.IO.Compression.ZipFile]::OpenRead($CoreZip)
  try {
    $required=@('main.js','package.json','html-autosync.js','preload.js','engine-preload.js','native-fs-shim.js','engine-bridge.js','control.html','control.js','control.css')
    $names=@($archive.Entries | ForEach-Object {$_.FullName})
    foreach($name in $required){if($names -notcontains $name){throw ('Core archive is missing '+$name)}}
  } finally {$archive.Dispose()}
}
try {
  VerifyCore
  if($SelfTest){Report 'PET v2.9.1 compact package: PASS (archive hash and all core files).';exit 0}
  # Always stop the dedicated PET Electron runtime before modifying its app data.
  if($Restart -and (Test-Path -LiteralPath $Exe)) {
    try {
      $processes=@(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction Stop | Where-Object {
        $_.ExecutablePath -eq $Exe -and $_.CommandLine -notmatch '--type='
      })
      foreach($p in $processes) {
        Report ('Closing previous PET instance: '+$p.ProcessId)
        & taskkill.exe /T /F /PID $p.ProcessId 2>&1 | Out-Null
      }
      if($processes.Count -gt 0){Start-Sleep -Milliseconds 800}
    } catch { Report ('Warning: could not close previous PET: '+$_.Exception.Message) }
  }
  $installed=''
  try {if(Test-Path -LiteralPath $Stamp){$installed=[System.IO.File]::ReadAllText($Stamp).Trim()}} catch {}
  if($installed -ne $CoreHash -or !(Test-Path -LiteralPath (Join-Path $AppDir 'main.js'))) {
    Report 'Installing / updating compact PET core...'
    New-Item -ItemType Directory -Force -Path $AppBase | Out-Null
    $stage=Join-Path $AppBase 'app-staging'
    if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Expand-Archive -LiteralPath $CoreZip -DestinationPath $stage -Force
    if(!(Test-Path -LiteralPath (Join-Path $stage 'main.js'))){throw 'PET core extraction failed.'}
    $old=Join-Path $AppBase 'app-previous'
    if(Test-Path -LiteralPath $old){Remove-Item -LiteralPath $old -Recurse -Force}
    if(Test-Path -LiteralPath $AppDir){Move-Item -LiteralPath $AppDir -Destination $old}
    Move-Item -LiteralPath $stage -Destination $AppDir
    [System.IO.File]::WriteAllText($Stamp,$CoreHash,[System.Text.Encoding]::ASCII)
    if(Test-Path -LiteralPath $old){Remove-Item -LiteralPath $old -Recurse -Force}
    Report 'Compact PET core installed.'
  }
  if(!(Test-Path -LiteralPath $Exe -PathType Leaf)) {
    Report 'Electron runtime not found. First-time download (~151 MB)...'
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
    $zip=Join-Path $HomeDir $ElectronZip
    $downloaded=$false
    if(!(Test-Path -LiteralPath $zip)) {
      $zip=Join-Path $env:TEMP $ElectronZip
      [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
      $url="https://github.com/electron/electron/releases/download/v$ElectronVersion/$ElectronZip"
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip -ErrorAction Stop
      $downloaded=$true
    }
    $actual=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $ElectronHash){throw 'Electron runtime SHA256 verification FAILED.'}
    $stage=Join-Path $RuntimeRoot "Electron-$ElectronVersion-extracting"
    if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    if(!(Test-Path -LiteralPath (Join-Path $stage 'electron.exe'))){throw 'Electron archive has no electron.exe.'}
    if(Test-Path -LiteralPath $RuntimeDir){Remove-Item -LiteralPath $RuntimeDir -Recurse -Force}
    Move-Item -LiteralPath $stage -Destination $RuntimeDir
    if($downloaded){Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue}
  }
  if($Mode -eq 'Safe'){$modeArg='--safe-window'}
  elseif($Mode -eq 'GPU'){$modeArg='--gpu-renderer'}
  else{$modeArg='--pet'}
  Report ('Starting compact PET: '+$Mode)
  Start-Process -FilePath $Exe -WorkingDirectory $AppBase -ArgumentList ('"{0}" {1}' -f $AppDir,$modeArg) -ErrorAction Stop | Out-Null
  Report 'Launch request sent to Electron.'
  exit 0
} catch {
  Report ('ERROR: '+$_.Exception.Message)
  Report ('See log: '+$Log)
  exit 1
}
