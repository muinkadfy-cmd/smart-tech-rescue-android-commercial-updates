$ErrorActionPreference='Stop'
# QA-only: runs on a clean ephemeral Windows 2022 GitHub runner.
# Exercise real MSI .120->.121 major upgrade, synthetic DPAPI state and a clean rollback.
$repo=$env:GITHUB_REPOSITORY
if($repo -ne 'muinkadfy-cmd/smart-tech-rescue-android-commercial-updates'){throw 'WRONG_REPO'}
$oldName='SmartTechRescueAndroid-Comercial-0.9.120-AUTOASSINADO-MANUAL.msi'
$newName='SmartTechRescueAndroid-Comercial-0.9.121-AUTOASSINADO-MANUAL.msi'
$dir=Join-Path $env:RUNNER_TEMP 'sarp-lot138-upgrade'
[IO.Directory]::CreateDirectory($dir)|Out-Null
$old=Join-Path $dir $oldName
$new=Join-Path (Join-Path $env:RUNNER_TEMP 'sarp-commercial') $newName
& gh release download 'v0.9.85.7.27-commercial-selfsigned' --repo $repo --pattern $oldName --dir $dir
if($LASTEXITCODE -ne 0){throw 'OLD_MSI_DOWNLOAD_FAILED'}
$oldSha='B83E0E310D5FA43957ADA6D08978A6B401F321CABAB945FB600601DC1D690F76'
$newSha='8D4A7D91EF4B47AB31DC1A40264B19A78F9F9483C8A051711C5CCF2BA759A270'
if((Get-FileHash $old -Algorithm SHA256).Hash -ne $oldSha){throw 'OLD_MSI_HASH_MISMATCH'}
if((Get-FileHash $new -Algorithm SHA256).Hash -ne $newSha){throw 'NEW_MSI_HASH_MISMATCH'}
'UPGRADE_BOTH_MSI_SHA256=PASS'
$installer=New-Object -ComObject WindowsInstaller.Installer
function Get-MsiProperties([string]$file){
 $db=$installer.OpenDatabase($file,0)
 $view=$db.OpenView('SELECT * FROM Property')
 $null=$view.Execute();$h=@{}
 try{while($row=$view.Fetch()){$h[$row.StringData(1)]=$row.StringData(2)}}
 finally{$null=$view.Close()}
 return $h
}
$o=Get-MsiProperties $old;$n=Get-MsiProperties $new
if($o.ProductVersion -ne '0.9.120' -or $n.ProductVersion -ne '0.9.121' -or
   $o.UpgradeCode -ne $n.UpgradeCode -or $o.ProductCode -eq $n.ProductCode){throw 'INVALID_MAJOR_UPGRADE_IDENTITIES'}
$exe='C:\Program Files\Smart Tech Rolândia\Smart Tech Rescue Android Comercial\SmartAndroidRescuePro.exe'
$offline='C:\Program Files\Smart Tech Rolândia\Smart Android Rescue Pro\SmartAndroidRescuePro.exe'
if((Test-Path $exe) -or (Test-Path $offline)){throw 'NON_CLEAN_RUNNER'}
function Msi([string]$verb,[string]$file,[string]$logName) {
 $log=Join-Path $dir $logName
 $p=Start-Process msiexec.exe -Wait -PassThru -ArgumentList @($verb,('"' + $file + '"'),'/qn','/norestart','/l*v',('"' + $log + '"'))
 if($p.ExitCode -ne 0){throw ('MSI_'+$logName+'_EXIT_'+$p.ExitCode)}
}
function Verify([string]$version,[string]$step){
 if(!(Test-Path $exe)){throw ($step+'_EXE_NOT_INSTALLED')}
 $v=(Get-Item $exe).VersionInfo.ProductVersion
 if($v -ne $version){throw ($step+'_VERSION_'+$v)}
 if(Test-Path $offline){throw ($step+'_OFFLINE_CHANGED')}
 Write-Output ($step+'=PASS '+$v)
}
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData
$state=Join-Path $env:LOCALAPPDATA 'SmartTechRescueAndroid\Licensing\license-state-production-v1.dpapi'
if(Test-Path $state){throw 'NON_CLEAN_TRIAL_STATE'}
[IO.Directory]::CreateDirectory((Split-Path $state))|Out-Null
$raw=[Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
$entropy=[Text.Encoding]::UTF8.GetBytes('SARP-QA-ONLY-MSI-LOT138')
$payload=[Security.Cryptography.ProtectedData]::Protect($raw,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
[IO.File]::WriteAllBytes($state,$payload)
$stateSha=(Get-FileHash $state -Algorithm SHA256).Hash
function VerifyState([string]$step) {
 if(!(Test-Path $state) -or (Get-FileHash $state -Algorithm SHA256).Hash -ne $stateSha){throw ($step+'_DPAPI_STATE_MUTATED')}
 $unsealed=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($state),$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 if(![Linq.Enumerable]::SequenceEqual([byte[]]$raw,[byte[]]$unsealed)){throw ($step+'_DPAPI_UNPROTECT_FAIL')}
 Write-Output ($step+'_DPAPI_STATE_PRESERVED=PASS')
}
$oldInstalled=$false;$newInstalled=$false
try {
 Msi '/i' $old 'install-old-120.log';$oldInstalled=$true
 Verify '0.9.85.7.27' 'OLD_120_INSTALLED'
 VerifyState 'OLD_120'
 Msi '/i' $new 'upgrade-new-121.log';$newInstalled=$true;$oldInstalled=$false
 Verify '0.9.85.7.28' 'UPGRADE_TO_121'
 VerifyState 'UPGRADE_TO_121'
 $oldReg=Join-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' $o.ProductCode
 if(Test-Path $oldReg){throw 'OLD_PRODUCT_STILL_REGISTERED'}
 Write-Output 'OLD_PRODUCT_REMOVED_DURING_UPGRADE=PASS'
 Msi '/x' $n.ProductCode 'uninstall-new-121.log';$newInstalled=$false
 if(Test-Path $exe){throw 'NEW_UNINSTALL_LEFT_EXE'}
 VerifyState 'POST_NEW_UNINSTALL'
 Msi '/i' $old 'rollback-reinstall-old-120.log';$oldInstalled=$true
 Verify '0.9.85.7.27' 'ROLLBACK_TO_120'
 VerifyState 'ROLLBACK_TO_120'
 Msi '/x' $o.ProductCode 'cleanup-uninstall-old-120.log';$oldInstalled=$false
 if(Test-Path $exe){throw 'OLD_UNINSTALL_LEFT_EXE'}
 VerifyState 'POST_ROLLBACK_UNINSTALL'
 Write-Output 'MAJOR_UPGRADE_AND_ROLLBACK=PASS; OFFLINE_ISOLATION=PASS; DPAPI_QA_PRESERVED=PASS'
}finally{
 if($newInstalled){try{Msi '/x' $n.ProductCode 'cleanup-new.log'}catch{Write-Warning 'CLEANUP_NEW_FAILED'}}
 if($oldInstalled){try{Msi '/x' $o.ProductCode 'cleanup-old.log'}catch{Write-Warning 'CLEANUP_OLD_FAILED'}}
}
