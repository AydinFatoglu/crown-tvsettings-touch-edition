# Crown TvSettings V1.4.7 Touch Edition (accessory-only visible list and BLE pairing fix) - clean APK rebuild; no ADB or system writes.
param([string]$Root = "$env:USERPROFILE\Downloads\Crown_TvSettings_Extract")
$ErrorActionPreference = 'Stop'
$src = Join-Path $Root 'TouchFix_V1_4_6_20261127_011623\CrownTvSettings_TouchEdition_V1_4_6.apk'
$work = Join-Path $Root ('TouchFix_V1_4_7_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$java = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
$sdk = "$env:LOCALAPPDATA\Android\Sdk\build-tools\37.0.0"
$signer = Join-Path $sdk 'lib\apksigner.jar'
$zipalign = Join-Path $sdk 'zipalign.exe'
$key = Join-Path $Root 'PlatformKeys\platform.pk8'
$cert = Join-Path $Root 'PlatformKeys\platform.x509.pem'
$tool = Join-Path $Root 'apktool_2.11.1.jar'
$expectedSource = '3B0D4E9E07F1BBDBAEA9AC02D84F80FD15D0280BF920E807BDE10D3320D4305A'
$expectedSigner = 'c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8'
$expectedTool = '56D59C524FC764263BA8D345754D8DAF55B1887818B15CD3B594F555D249E2DB'
$aapt = Join-Path $sdk 'aapt2.exe'
$old = 'com.android.settings.files'
$new = 'com.crown.tvsettings.files'
function Native([string]$Exe,[string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $lines = @(& $Exe @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $rc = $LASTEXITCODE
    if ($rc -ne 0) { $lines | Out-Host; throw "Exit $rc from $Exe" }
    $lines
}
function Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Check-Signer([string]$Path) {
    $v = @(Native $java @('-jar',$signer,'verify','--verbose','--print-certs',$Path))
    if (($v -join "`n") -notmatch [regex]::Escape($expectedSigner)) { throw 'Platform signature mismatch.' }
    $v | Out-Host
}
foreach($p in @($src,$java,$signer,$zipalign,$aapt,$tool,$key,$cert)) { if (!(Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing: $p" } }
if ((Sha $src) -ne $expectedSource) { throw 'V1.4.6 APK SHA256 mismatch.' }
if ((Sha $tool) -ne $expectedTool) { throw 'Apktool SHA256 mismatch.' }
New-Item -ItemType Directory -Path $work | Out-Null
Start-Transcript -Path (Join-Path $work 'Build_Log.txt') | Out-Null
try {
    Check-Signer $src
    $beforeManifest = @(Native $aapt @('dump','xmltree','--file','AndroidManifest.xml',$src))
    $beforeManifest | Set-Content -LiteralPath (Join-Path $work 'Manifest_Before.txt') -Encoding UTF8
    $authorityPattern = 'android:authorities\(0x[0-9a-fA-F]+\)="' + [regex]::Escape($new) + '"'
    if (@($beforeManifest | Where-Object { $_ -match $authorityPattern }).Count -ne 1) { throw 'Expected one Crown provider authority.' }
    Write-Host '[OK] V1.4.6 APK and manifest verified.' -ForegroundColor Green
    $decoded = Join-Path $work 'decoded'
    Native $java @('-jar',$tool,'d','-r','-f','-o',$decoded,$src) | Out-Host
    function Read-Smali([string]$Path) { [IO.File]::ReadAllText($Path).Replace("`r`n","`n") }
    function Write-Smali([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
    function Text-Sha([string]$Text) {
        $h=[Security.Cryptography.SHA256]::Create()
        try { ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','') } finally { $h.Dispose() }
    }
    $relative='smali\com\android\tv\settings\util\bluetooth\BluetoothScanner$Receiver.smali'
    $activity=Join-Path $decoded $relative
    $original=Read-Smali $activity
    $expectedScanner='959FD8E1150F8292AD455C3A45BE9EE6A7A47F3A120587D8DF67F84EB9308688'
    if((Text-Sha $original) -ne $expectedScanner){throw 'Scanner code differs from the inspected Crown archive. No patch applied. Send decoded BluetoothScanner$Receiver.smali.'}
    function Replace-Once([string]$Text,[string]$Old,[string]$New) {
        $Old=$Old.Replace("`r`n","`n"); $New=$New.Replace("`r`n","`n")
        $count=[regex]::Matches($Text,[regex]::Escape($Old)).Count
        if($count -ne 1){$first=(($Old -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1); throw "Patch anchor count=$count first='$first'"}
        $Text.Replace($Old,$New)
    }
    function Replace-Method([string]$Text,[string]$Name,[string]$New) {
        $New=$New.Replace("`r`n","`n")
        $pattern='(?ms)^\.method public '+[regex]::Escape($Name)+'\(\)V\n.*?^\.end method[ \t]*$'
        $matches=@([regex]::Matches($Text,$pattern))
        if($matches.Count -ne 1){throw "Method not unique: $Name"}
        $m=$matches[0]
        $Text.Substring(0,$m.Index)+$New+$Text.Substring($m.Index+$m.Length)
    }
    # Canonical comparison for the one edited class: ignore formatting/debug line numbers only.
    # Normalize branch names within each method (baksmali may renumber labels).
    function Canonical-Smali([string]$Text) {
        $result=New-Object 'System.Collections.Generic.List[string]'
        $labels=@{}
        $inMethod=$false
        foreach($raw in ($Text -split "`n")){
            $line=$raw.Trim()
            if(!$line -or $line -match '^\.line\s+\d+$'){continue}
            if($line.StartsWith('.method ')){$labels=@{};$inMethod=$true}
            if($inMethod -and $line -notmatch '^const-string'){
                $line=[regex]::Replace($line,'(?<![\w;])(?:\:)(?:cond|goto|try_start|try_end|catchall|catch|pswitch|sswitch|array)_[0-9a-f]+\b',{
                    param($m)
                    $name=$m.Value
                    if(!$labels.ContainsKey($name)){$labels[$name]=':L'+$labels.Count}
                    $labels[$name]
                })
            }
            $result.Add($line)
            if($line -eq '.end method'){$inMethod=$false}
        }
        # Baksmali may emit multiple labels for the same bytecode address. Collapse
        # adjacent label aliases, then renumber again so the comparison is semantic.
        $aliases=@{}
        $primary=$null
        $previousWasLabel=$false
        foreach($line in $result){
            if($line -match '^:L\d+$'){
                if(!$previousWasLabel){$primary=$line}
                $aliases[$line]=$primary
                $previousWasLabel=$true
            } else {$previousWasLabel=$false}
        }
        $collapsed=New-Object 'System.Collections.Generic.List[string]'
        $last=$null
        foreach($line in $result){
            $normalized=[regex]::Replace($line,':L\d+\b',{param($m) if($aliases.ContainsKey($m.Value)){$aliases[$m.Value]}else{$m.Value}})
            if($normalized -match '^:L\d+$' -and $normalized -eq $last){continue}
            $collapsed.Add($normalized)
            $last=$normalized
        }
        $renumber=@{}
        $final=New-Object 'System.Collections.Generic.List[string]'
        foreach($line in $collapsed){
            $normalized=[regex]::Replace($line,':L\d+\b',{param($m) if(!$renumber.ContainsKey($m.Value)){$renumber[$m.Value]=':L'+$renumber.Count};$renumber[$m.Value]})
            $final.Add($normalized)
        }
        $final -join "`n"
    }
    function Canonical-SmaliSorted([string]$Text) {
        $Text=$Text.Replace("`r`n","`n")
        $pattern='(?ms)^\.method .*?^\.end method[ \t]*$'
        $methods=@([regex]::Matches($Text,$pattern) | ForEach-Object { Canonical-Smali $_.Value } | Sort-Object)
        $outside=[regex]::Replace($Text,$pattern,'')
        (Canonical-Smali $outside)+"`n---METHODS---`n"+($methods -join "`n---METHOD---`n")
    }
    if($false) {
    $patched=$original
    $replacement=@'
.method public scanNow()V
    .locals 2

    sget-boolean v0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mKeepScanning:Z
    if-nez v0, :cond_0
    return-void

    :cond_0
    iget-boolean v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mRegistered:Z
    if-nez v0, :cond_1
    return-void

    :cond_1
    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mBtAdapter:Landroid/bluetooth/BluetoothAdapter;
    if-eqz v0, :cond_2
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->isEnabled()Z
    move-result v1
    if-nez v1, :cond_3

    :cond_2
    const-string v0, "CrownBtScan"
    const-string v1, "Adapter unavailable; retry in 2500ms"
    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    const-wide/16 v0, 0x9c4
    invoke-direct {p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->crownScheduleScan(J)V
    return-void

    :cond_3
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->isDiscovering()Z
    move-result v1
    if-eqz v1, :cond_4
    const-string v0, "CrownBtScan"
    const-string v1, "Discovery still active; defer without cancel"
    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    const-wide/16 v0, 0xfa0
    invoke-direct {p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->crownScheduleScan(J)V
    return-void

    :cond_4
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->startDiscovery()Z
    move-result v0
    if-nez v0, :cond_5
    const-string v0, "CrownBtScan"
    const-string v1, "startDiscovery=false; retry in 2500ms"
    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
    const-wide/16 v0, 0x9c4
    invoke-direct {p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->crownScheduleScan(J)V
    return-void

    :cond_5
    const-string v0, "CrownBtScan"
    const-string v1, "startDiscovery=true; watchdog in 20000ms"
    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    invoke-direct {p0}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->sendScanningStarted()V
    const-wide/16 v0, 0x4e20
    invoke-direct {p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->crownScheduleScan(J)V
    return-void
.end method
'@
    $patched=Replace-Method $patched 'scanNow' $replacement
    $replacement=@'
.method public stopNow()V
    .locals 2

    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mListenerLock:Ljava/lang/Object;
    monitor-enter v0

    :try_start_0
    iget-object v1, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mClients:Ljava/util/ArrayList;
    invoke-virtual {v1}, Ljava/util/ArrayList;->size()I
    move-result v1
    monitor-exit v0
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    if-nez v1, :cond_2
    const/4 v0, 0x0
    sput-boolean v0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mKeepScanning:Z

    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mHandler:Landroid/os/Handler;
    iget-object v1, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mScanTask:Ljava/lang/Runnable;
    invoke-virtual {v0, v1}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V
    iget-object v1, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mStopTask:Ljava/lang/Runnable;
    invoke-virtual {v0, v1}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V

    iget-boolean v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mRegistered:Z
    if-eqz v0, :cond_2

    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mBtAdapter:Landroid/bluetooth/BluetoothAdapter;
    if-eqz v0, :cond_0
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->isDiscovering()Z
    move-result v1
    if-eqz v1, :cond_0
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->cancelDiscovery()Z
    move-result v1
    if-eqz v1, :cond_1

    :cond_0
    const-string v0, "CrownBtScan"
    const-string v1, "Stop: no discovery or cancel accepted"
    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    goto :goto_0

    :cond_1
    const-string v0, "CrownBtScan"
    const-string v1, "Stop: cancelDiscovery=false"
    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I

    :goto_0
    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mContext:Landroid/content/Context;
    invoke-virtual {v0, p0}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V
    const/4 v0, 0x0
    iput-boolean v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mRegistered:Z
    const-string v0, "CrownBtScan"
    const-string v1, "Stopped; callbacks removed, receiver unregistered"
    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    :cond_2
    return-void

    :catchall_0
    move-exception p0
    monitor-exit v0
    throw p0
.end method
'@
    $patched=Replace-Method $patched 'stopNow' $replacement
    $oldBlock=@'
    .line 249
    invoke-virtual {p0}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->scanNow()V
'@
    $newBlock=@'
    .line 249
    const-wide/16 v0, 0x5dc
    invoke-direct {p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->crownScheduleScan(J)V
'@
    $patched=Replace-Once $patched $oldBlock $newBlock
    $oldBlock=@'
    .line 462
    iget-object p1, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mHandler:Landroid/os/Handler;

    iget-object p0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mScanTask:Ljava/lang/Runnable;

    const-wide/16 v0, 0xfa0

    invoke-virtual {p1, p0, v0, v1}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
'@
    $newBlock=@'
    .line 462
    const-string p1, "CrownBtScan"
    const-string p2, "DISCOVERY_FINISHED; next scan in 4000ms"
    invoke-static {p1, p2}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    const-wide/16 v0, 0xfa0
    invoke-direct {p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->crownScheduleScan(J)V
'@
    $patched=Replace-Once $patched $oldBlock $newBlock
    $oldBlock=@'
    .line 267
    iget-object p1, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mHandler:Landroid/os/Handler;

    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mStopTask:Ljava/lang/Runnable;

    invoke-virtual {p1, v0}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V

    .line 268
    iget-object p1, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mHandler:Landroid/os/Handler;

    iget-object p0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mStopTask:Ljava/lang/Runnable;

    const-wide/16 v0, 0x4e20

    invoke-virtual {p1, p0, v0, v1}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

'@
    $newBlock=@'
    .line 267
    invoke-virtual {p0}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->stopNow()V

'@
    $patched=Replace-Once $patched $oldBlock $newBlock
    $oldBlock=@'
    :cond_0
    const-string v2, "\u0000"
'@
    $newBlock=@'
    :cond_0
    const-string v2, "CrownBtScanFound"

    invoke-static {v2, p2}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    const-string v2, "\u0000"
'@
    $patched=Replace-Once $patched $oldBlock $newBlock
    $oldBlock=@'
.method private sendDeviceAdded(
'@
    $newBlock=@'
.method private crownScheduleScan(J)V
    .locals 2

    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mHandler:Landroid/os/Handler;
    iget-object v1, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mScanTask:Ljava/lang/Runnable;
    invoke-virtual {v0, v1}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V
    sget-boolean v0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mKeepScanning:Z
    if-eqz v0, :cond_0
    iget-boolean v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mRegistered:Z
    if-eqz v0, :cond_0
    iget-object v0, p0, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->mHandler:Landroid/os/Handler;
    invoke-virtual {v0, v1, p1, p2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

    :cond_0
    return-void
.end method

.method private sendDeviceAdded(
'@
    $patched=Replace-Once $patched $oldBlock $newBlock
    $audit=Join-Path $work 'Patch_Audit'
    New-Item -ItemType Directory -Path $audit | Out-Null
    Write-Smali (Join-Path $audit 'BluetoothScanner_Receiver_Before.smali') $original
    Write-Smali $activity $patched
    Write-Smali (Join-Path $audit 'BluetoothScanner_Receiver_After.smali') $patched
    Write-Host '[OK] Scanner lifecycle, retry, watchdog and diagnostic logging patched.' -ForegroundColor Green
    }
    function Replace-ExactMethod([string]$Text,[string]$Header,[string]$New) {
        $New=$New.Replace("`r`n","`n")
        $pattern='(?ms)^'+[regex]::Escape($Header)+'\n.*?^\.end method[ \t]*$'
        $matches=@([regex]::Matches($Text,$pattern))
        if($matches.Count -ne 1){throw "Method not unique: $Header"}
        $m=$matches[0]
        $Text.Substring(0,$m.Index)+$New+$Text.Substring($m.Index+$m.Length)
    }
    $base='smali\com\android\tv\settings'
    $scannerRelative=Join-Path $base 'util\bluetooth\BluetoothScanner$Receiver.smali'
    $criteriaRelative=Join-Path $base 'util\bluetooth\BluetoothDeviceCriteria.smali'
    $pairerRelative=Join-Path $base 'accessories\BluetoothDevicePairer.smali'
    $pairingRequestRelative=Join-Path $base 'accessories\BluetoothPairingRequest.smali'
    $uiRelative=Join-Path $base 'accessories\AddAccessoryPreferenceFragment.smali'
    $expectedTextHashes=@{
        $scannerRelative='959FD8E1150F8292AD455C3A45BE9EE6A7A47F3A120587D8DF67F84EB9308688'
        $criteriaRelative='EA65CD753F051A61489E43BEE39274D612726E33ECAE7C15B7A1BC5273D3199B'
        $pairerRelative='452F442C570C68F57C8DEAA213186E085776BE9121B5DFC5923AA636539CE1BA'
        $pairingRequestRelative='2A60EDB0ADAD77F21F94F3D9FA2D082F58D4761738580A4F14DEBEA82E258647'
        $uiRelative='4760D910A6A3124F9D17221F4CD2A3F4F971D48AB692700A9D68E561E64273BE'
    }
    $originalByRelative=@{}
    foreach($rel in $expectedTextHashes.Keys){
        $text=Read-Smali (Join-Path $decoded $rel)
        if((Text-Sha $text) -ne $expectedTextHashes[$rel]){throw "Unexpected V1.4.6 Smali: $rel"}
        $originalByRelative[$rel]=$text
    }

    # Scanner: valid-MAC guard, null/blank-name fallback, detailed FOUND diagnostics,
    # address-deduped client delivery and cache re-evaluation on every repeated FOUND.
    $scanner=$originalByRelative[$scannerRelative]
    $oldBlock=@'
    const-string p1, "android.bluetooth.device.extra.DEVICE"

    .line 370
    invoke-virtual {p2, p1}, Landroid/content/Intent;->getParcelableExtra(Ljava/lang/String;)Landroid/os/Parcelable;

    move-result-object p1

    check-cast p1, Landroid/bluetooth/BluetoothDevice;

    .line 371
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;

    move-result-object p2

    .line 372
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getName()Ljava/lang/String;

    move-result-object v0

    if-eqz p2, :cond_6

    if-nez v0, :cond_0

    goto :goto_2

    :cond_0
    const-string v2, "CrownBtScanFound"

    invoke-static {v2, p2}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    const-string v2, "\u0000"
'@
    $newBlock=@'
    const-string p1, "android.bluetooth.device.extra.DEVICE"

    .line 370
    invoke-virtual {p2, p1}, Landroid/content/Intent;->getParcelableExtra(Ljava/lang/String;)Landroid/os/Parcelable;

    move-result-object p1

    check-cast p1, Landroid/bluetooth/BluetoothDevice;

    if-eqz p1, :cond_6

    .line 371
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;

    move-result-object p2

    if-eqz p2, :cond_6

    invoke-static {p2}, Landroid/bluetooth/BluetoothAdapter;->checkBluetoothAddress(Ljava/lang/String;)Z

    move-result v2

    if-eqz v2, :cond_6

    .line 372
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getName()Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :cond_20

    invoke-virtual {v0}, Ljava/lang/String;->trim()Ljava/lang/String;

    move-result-object v0

    invoke-virtual {v0}, Ljava/lang/String;->isEmpty()Z

    move-result v2

    if-eqz v2, :cond_21

    :cond_20
    move-object v0, p2

    :cond_21
    const-string v2, "CrownBtScanFound"
    invoke-static {v2, p2}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    invoke-static {p1, p2, v0}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->crownLogFound(Landroid/bluetooth/BluetoothDevice;Ljava/lang/String;Ljava/lang/String;)V
    const-string v2, "\u0000"
'@
    $scanner=Replace-Once $scanner $oldBlock $newBlock
    $oldBlock=@'
.method private sendDeviceAdded(
'@
    $newBlock=@'
.method private static crownLogFound(Landroid/bluetooth/BluetoothDevice;Ljava/lang/String;Ljava/lang/String;)V
    .locals 4

    new-instance v0, Ljava/lang/StringBuilder;
    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
    const-string v1, "FOUND address="
    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string p1, " name="
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string p1, " type="
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {p0}, Landroid/bluetooth/BluetoothDevice;->getType()I
    move-result p1
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string p1, " class="
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {p0}, Landroid/bluetooth/BluetoothDevice;->getBluetoothClass()Landroid/bluetooth/BluetoothClass;
    move-result-object p1
    if-eqz p1, :cond_0
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothClass;->getDeviceClass()I
    move-result p1
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    goto :goto_0

    :cond_0
    const-string p1, "UNKNOWN"
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    :goto_0
    const-string p1, " uuids="
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {p0}, Landroid/bluetooth/BluetoothDevice;->getUuids()[Landroid/os/ParcelUuid;
    move-result-object p0
    invoke-static {p0}, Ljava/util/Arrays;->toString([Ljava/lang/Object;)Ljava/lang/String;
    move-result-object p0
    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object p0
    const-string p1, "CrownBtFilter"
    invoke-static {p1, p0}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    return-void
.end method

.method private sendDeviceAdded(
'@
    $scanner=Replace-Once $scanner $oldBlock $newBlock
    $oldBlock=@'
    check-cast v2, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$ClientRecord;

    .line 492
    iget-object v3, v2, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$ClientRecord;->matchers:Ljava/util/List;
'@
    $newBlock=@'
    check-cast v2, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$ClientRecord;

    iget-object v3, v2, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$ClientRecord;->devices:Ljava/util/ArrayList;
    invoke-virtual {v3, p1}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
    move-result v3
    if-nez v3, :cond_1

    .line 492
    iget-object v3, v2, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$ClientRecord;->matchers:Ljava/util/List;
'@
    $scanner=Replace-Once $scanner $oldBlock $newBlock
    $oldBlock=@'
    invoke-virtual {p1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result p1

    if-eqz p1, :cond_5

    goto :goto_2
'@
    $newBlock=@'
    invoke-virtual {p1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result p1

    if-eqz p1, :cond_5

    goto :goto_20
'@
    $scanner=Replace-Once $scanner $oldBlock $newBlock
    $oldBlock=@'
    if-eq p1, v0, :cond_6
'@
    $newBlock=@'
    if-eq p1, v0, :goto_20
'@
    $scanner=Replace-Once $scanner $oldBlock $newBlock
    $oldBlock=@'
    invoke-direct {p0, v2}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->sendDeviceChanged(Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Device;)V

    goto :goto_5
'@
    $newBlock=@'
    invoke-direct {p0, v2}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->sendDeviceChanged(Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Device;)V

    :goto_20
    invoke-direct {p0, v2}, Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Receiver;->sendDeviceAdded(Lcom/android/tv/settings/util/bluetooth/BluetoothScanner$Device;)V

    goto :goto_5
'@
    $scanner=Replace-Once $scanner $oldBlock $newBlock

    # Criteria: keep subclass policy, but validate addresses, tolerate missing CoD,
    # and let only the Pairer-specific base matcher accept class 0/UNKNOWN.
    $criteria=$originalByRelative[$criteriaRelative]
    $oldBlock=@'
# virtual methods
'@
    $newBlock=@'
.method private static crownLogDecision(Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;ZLjava/lang/String;)V
    .locals 4

    new-instance v0, Ljava/lang/StringBuilder;
    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
    const-string v1, "criteria="
    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {p1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
    move-result-object p1
    invoke-virtual {p1}, Ljava/lang/Class;->getSimpleName()Ljava/lang/String;
    move-result-object p1
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string p1, " address="
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    if-eqz p0, :cond_0
    invoke-virtual {p0}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object p0
    goto :goto_0
    :cond_0
    const-string p0, "UNKNOWN"
    :goto_0
    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string p0, " accept="
    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(Z)Ljava/lang/StringBuilder;
    const-string p0, " reason="
    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, p3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object p0
    const-string p1, "CrownBtFilter"
    invoke-static {p1, p0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    return-void
.end method

# virtual methods
'@
    $criteria=Replace-Once $criteria $oldBlock $newBlock
    $replacement=@'
.method public final isMatchingDevice(Landroid/bluetooth/BluetoothDevice;)Z
    .locals 4

    const/4 v0, 0x0
    if-nez p1, :cond_0
    const-string v1, "null_device"
    invoke-static {p1, p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->crownLogDecision(Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;ZLjava/lang/String;)V
    return v0

    :cond_0
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object v1
    if-eqz v1, :cond_5
    invoke-static {v1}, Landroid/bluetooth/BluetoothAdapter;->checkBluetoothAddress(Ljava/lang/String;)Z
    move-result v2
    if-eqz v2, :cond_5
    invoke-virtual {p0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->isMatchingMacAddress(Ljava/lang/String;)Z
    move-result v1
    if-eqz v1, :cond_4

    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getBluetoothClass()Landroid/bluetooth/BluetoothClass;
    move-result-object v1
    if-eqz v1, :cond_1
    invoke-virtual {v1}, Landroid/bluetooth/BluetoothClass;->getMajorDeviceClass()I
    move-result v2
    invoke-virtual {v1}, Landroid/bluetooth/BluetoothClass;->getDeviceClass()I
    move-result v3
    goto :goto_0

    :cond_1
    const/4 v2, 0x0
    const/4 v3, 0x0

    :goto_0
    invoke-virtual {p0, v2}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->isMatchingMajorDeviceClass(I)Z
    move-result v1
    if-eqz v1, :cond_3
    invoke-virtual {p0, v3}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->isMatchingDeviceClass(I)Z
    move-result v1
    if-eqz v1, :cond_2
    const/4 v0, 0x1
    const-string v1, "accepted"
    invoke-static {p1, p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->crownLogDecision(Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;ZLjava/lang/String;)V
    return v0

    :cond_2
    const-string v1, "device_class_mismatch"
    invoke-static {p1, p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->crownLogDecision(Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;ZLjava/lang/String;)V
    return v0

    :cond_3
    const-string v1, "major_class_mismatch"
    invoke-static {p1, p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->crownLogDecision(Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;ZLjava/lang/String;)V
    return v0

    :cond_4
    const-string v1, "mac_pattern_mismatch"
    invoke-static {p1, p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->crownLogDecision(Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;ZLjava/lang/String;)V
    return v0

    :cond_5
    const-string v1, "invalid_address"
    invoke-static {p1, p0, v0, v1}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;->crownLogDecision(Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;ZLjava/lang/String;)V
    return v0
.end method
'@
    $criteria=Replace-ExactMethod $criteria '.method public final isMatchingDevice(Landroid/bluetooth/BluetoothDevice;)Z' $replacement

    # Pairer-only unfiltered matcher plus address-deduped visible list and LE transport
    # allowlist for the two known HID remotes. Manual selection remains mandatory.
    $pairer=$originalByRelative[$pairerRelative]
    $oldBlock=@'
.field private final mOpenConnectionCallback:Lcom/android/tv/settings/accessories/BluetoothDevicePairer$OpenConnectionCallback;

.field private mStatus:I
'@
    $newBlock=@'
.field private final mOpenConnectionCallback:Lcom/android/tv/settings/accessories/BluetoothDevicePairer$OpenConnectionCallback;

.field private final mPairingRequestReceiver:Landroid/content/BroadcastReceiver;

.field private mPairingRequestReceiverRegistered:Z

.field private mStatus:I
'@
    $pairer=Replace-Once $pairer $oldBlock $newBlock
    $oldBlock=@'
    iput-object v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mLinkStatusReceiver:Landroid/content/BroadcastReceiver;

    .line 248
    new-instance v0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer$3;
'@
    $newBlock=@'
    iput-object v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mLinkStatusReceiver:Landroid/content/BroadcastReceiver;

    new-instance v0, Lcom/android/tv/settings/accessories/BluetoothPairingRequest;
    invoke-direct {v0}, Lcom/android/tv/settings/accessories/BluetoothPairingRequest;-><init>()V
    iput-object v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mPairingRequestReceiver:Landroid/content/BroadcastReceiver;

    .line 248
    new-instance v0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer$3;
'@
    $pairer=Replace-Once $pairer $oldBlock $newBlock
    $oldBlock=@'
    invoke-virtual {v1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    .line 307
    new-instance v0, Landroid/content/Intent;
'@
    $newBlock=@'
    invoke-virtual {v1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    iget-object v1, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mBluetoothDeviceCriteria:Ljava/util/ArrayList;
    new-instance v0, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;
    invoke-direct {v0}, Lcom/android/tv/settings/util/bluetooth/BluetoothDeviceCriteria;-><init>()V
    invoke-virtual {v1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
    const-string v0, "CrownBtFilter"
    const-string v1, "Pairer diagnostic matcher enabled: valid MAC devices are manually selectable"
    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    .line 307
    new-instance v0, Landroid/content/Intent;
'@
    $pairer=Replace-Once $pairer $oldBlock $newBlock
    $replacement=@'
.method private onDeviceFound(Landroid/bluetooth/BluetoothDevice;)V
    .locals 8

    if-eqz p1, :cond_6
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object v0
    if-eqz v0, :cond_6
    invoke-static {v0}, Landroid/bluetooth/BluetoothAdapter;->checkBluetoothAddress(Ljava/lang/String;)Z
    move-result v1
    if-eqz v1, :cond_6

    invoke-static {p1}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->crownIsAccessory(Landroid/bluetooth/BluetoothDevice;)Z
    move-result v1
    if-eqz v1, :cond_7

    iget-object v1, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mVisibleDevices:Ljava/util/ArrayList;
    invoke-virtual {v1}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
    move-result-object v2

    :goto_0
    invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
    move-result v3
    if-eqz v3, :cond_2
    invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
    move-result-object v3
    check-cast v3, Landroid/bluetooth/BluetoothDevice;
    invoke-virtual {v3}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object v4
    if-eqz v4, :goto_0
    invoke-virtual {v0, v4}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    move-result v4
    if-eqz v4, :goto_0
    new-instance v5, Ljava/lang/StringBuilder;
    invoke-direct {v5}, Ljava/lang/StringBuilder;-><init>()V
    const-string v6, "cache hit address="
    invoke-virtual {v5, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v5, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v5}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v5
    const-string v6, "CrownBtVisible"
    invoke-static {v6, v5}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    return-void

    :cond_2
    invoke-virtual {v1, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getName()Ljava/lang/String;
    move-result-object v5
    if-eqz v5, :cond_3
    invoke-virtual {v5}, Ljava/lang/String;->trim()Ljava/lang/String;
    move-result-object v5
    invoke-virtual {v5}, Ljava/lang/String;->isEmpty()Z
    move-result v6
    if-eqz v6, :cond_4
    :cond_3
    move-object v5, v0

    :cond_4
    new-instance v7, Ljava/lang/StringBuilder;
    invoke-direct {v7}, Ljava/lang/StringBuilder;-><init>()V
    const-string v6, "visible add address="
    invoke-virtual {v7, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v7, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string v0, " name="
    invoke-virtual {v7, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v7, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    const-string v0, " class="
    invoke-virtual {v7, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {p1}, Landroid/bluetooth/BluetoothDevice;->getBluetoothClass()Landroid/bluetooth/BluetoothClass;
    move-result-object v6
    if-eqz v6, :cond_5
    invoke-virtual {v6}, Landroid/bluetooth/BluetoothClass;->getDeviceClass()I
    move-result v6
    invoke-virtual {v7, v6}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    goto :goto_1
    :cond_5
    const-string v6, "UNKNOWN"
    invoke-virtual {v7, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    :goto_1
    const-string v6, " count="
    invoke-virtual {v7, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1}, Ljava/util/ArrayList;->size()I
    move-result v6
    invoke-virtual {v7, v6}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    invoke-virtual {v7}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v7
    const-string v6, "CrownBtVisible"
    invoke-static {v6, v7}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->updatePairingState()V
    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->updateListener()V
    return-void

    :cond_7
    new-instance v1, Ljava/lang/StringBuilder;
    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V
    const-string v2, "hidden non-accessory address="
    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v1
    const-string v2, "CrownBtVisible"
    invoke-static {v2, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    return-void

    :cond_6
    const-string v0, "CrownBtVisible"
    const-string v1, "visible reject: null device or invalid address"
    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
    return-void
.end method
'@
    $pairer=Replace-ExactMethod $pairer '.method private onDeviceFound(Landroid/bluetooth/BluetoothDevice;)V' $replacement
    $replacement=@'
.method private getBluetoothConnector()Lcom/android/tv/settings/accessories/BluetoothDevicePairer$BluetoothConnector;
    .locals 5

    iget-object v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mTarget:Landroid/bluetooth/BluetoothDevice;
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object v4
    const-string v1, "20:0B:16:5C:13:94"
    invoke-virtual {v1, v4}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    move-result v1
    if-nez v1, :cond_1
    const-string v1, "18:BF:1C:96:9D:76"
    invoke-virtual {v1, v4}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    move-result v1
    if-nez v1, :cond_1

    invoke-virtual {v0}, Landroid/bluetooth/BluetoothDevice;->getBluetoothClass()Landroid/bluetooth/BluetoothClass;
    move-result-object v0
    if-eqz v0, :cond_0
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothClass;->getMajorDeviceClass()I
    move-result v0
    const/16 v1, 0x400
    if-eq v0, v1, :cond_2
    const/16 v1, 0x500
    if-eq v0, v1, :cond_1
    goto :goto_0

    :cond_0
    const/4 v0, 0x0
    :goto_0
    new-instance p0, Ljava/lang/StringBuilder;
    invoke-direct {p0}, Ljava/lang/StringBuilder;-><init>()V
    const-string v1, "Unhandled device class: "
    invoke-virtual {p0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {p0, v0}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    invoke-virtual {p0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object p0
    const-string v0, "BluetoothDevicePairer"
    invoke-static {v0, p0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    const/4 p0, 0x0
    return-object p0

    :cond_1
    const-string v0, "CrownBtPairing"
    const-string v1, "allowlisted BLE remote routed to HID connector"
    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    new-instance v0, Lcom/android/tv/settings/accessories/BluetoothInputDeviceConnector;
    iget-object v1, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mContext:Landroid/content/Context;
    iget-object v2, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mTarget:Landroid/bluetooth/BluetoothDevice;
    iget-object v3, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mHandler:Landroid/os/Handler;
    iget-object p0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mOpenConnectionCallback:Lcom/android/tv/settings/accessories/BluetoothDevicePairer$OpenConnectionCallback;
    invoke-direct {v0, v1, v2, v3, p0}, Lcom/android/tv/settings/accessories/BluetoothInputDeviceConnector;-><init>(Landroid/content/Context;Landroid/bluetooth/BluetoothDevice;Landroid/os/Handler;Lcom/android/tv/settings/accessories/BluetoothDevicePairer$OpenConnectionCallback;)V
    return-object v0

    :cond_2
    new-instance v0, Lcom/android/tv/settings/accessories/BluetoothA2dpConnector;
    iget-object v1, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mContext:Landroid/content/Context;
    iget-object v2, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mTarget:Landroid/bluetooth/BluetoothDevice;
    iget-object p0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mOpenConnectionCallback:Lcom/android/tv/settings/accessories/BluetoothDevicePairer$OpenConnectionCallback;
    invoke-direct {v0, v1, v2, p0}, Lcom/android/tv/settings/accessories/BluetoothA2dpConnector;-><init>(Landroid/content/Context;Landroid/bluetooth/BluetoothDevice;Lcom/android/tv/settings/accessories/BluetoothDevicePairer$OpenConnectionCallback;)V
    return-object v0
.end method
'@
    $pairer=Replace-ExactMethod $pairer '.method private getBluetoothConnector()Lcom/android/tv/settings/accessories/BluetoothDevicePairer$BluetoothConnector;' $replacement
    $replacement=@'
.method private startBonding()V
    .locals 4

    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->stopScanning()V
    const/4 v0, 0x3
    invoke-direct {p0, v0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->setStatus(I)V
    iget-object v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mTarget:Landroid/bluetooth/BluetoothDevice;
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothDevice;->getBondState()I
    move-result v1
    const/16 v2, 0xc
    if-eq v1, v2, :cond_3
    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->registerLinkStatusReceiver()V
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object v1
    const-string v2, "20:0B:16:5C:13:94"
    invoke-virtual {v2, v1}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    move-result v2
    if-nez v2, :cond_1
    const-string v2, "18:BF:1C:96:9D:76"
    invoke-virtual {v2, v1}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    move-result v2
    if-nez v2, :cond_1
    const-string v2, "CrownBtPairing"
    const-string v3, "AUTO transport for non-allowlisted device"
    invoke-static {v2, v3}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothDevice;->createBond()Z
    move-result v2
    goto :goto_0

    :cond_1
    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->registerPairingRequestReceiver()V
    new-instance v2, Ljava/lang/StringBuilder;
    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
    const-string v3, "forcing TRANSPORT_LE (2) address="
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v2
    const-string v3, "CrownBtPairing"
    invoke-static {v3, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    const/4 v2, 0x2
    invoke-virtual {v0, v2}, Landroid/bluetooth/BluetoothDevice;->createBond(I)Z
    move-result v2

    :goto_0
    invoke-static {v2}, Ljava/lang/String;->valueOf(Z)Ljava/lang/String;
    move-result-object v2
    const-string v3, "CrownBtPairing"
    invoke-static {v3, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    return-void

    :cond_3
    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->onBonded()V
    return-void
.end method
'@
    $pairer=Replace-ExactMethod $pairer '.method private startBonding()V' $replacement

    $pairingReceiverHelpers=@'
.method private static crownIsAccessory(Landroid/bluetooth/BluetoothDevice;)Z
    .locals 3

    if-eqz p0, :cond_2
    invoke-virtual {p0}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object v0
    const-string v1, "20:0B:16:5C:13:94"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "18:BF:1C:96:9D:76"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z
    move-result v1
    if-nez v1, :cond_0

    invoke-virtual {p0}, Landroid/bluetooth/BluetoothDevice;->getBluetoothClass()Landroid/bluetooth/BluetoothClass;
    move-result-object v0
    if-eqz v0, :cond_1
    invoke-virtual {v0}, Landroid/bluetooth/BluetoothClass;->getDeviceClass()I
    move-result v0
    and-int/lit16 v1, v0, 0x1f00
    const/16 v2, 0x500
    if-eq v1, v2, :cond_0
    const/16 v2, 0x400
    if-ne v1, v2, :cond_1
    const/16 v1, 0x400
    if-eq v0, v1, :cond_0
    const/16 v1, 0x404
    if-eq v0, v1, :cond_0
    const/16 v1, 0x408
    if-eq v0, v1, :cond_0
    const/16 v1, 0x410
    if-eq v0, v1, :cond_0
    const/16 v1, 0x418
    if-eq v0, v1, :cond_0
    const/16 v1, 0x41c
    if-eq v0, v1, :cond_0

    :cond_1
    invoke-virtual {p0}, Landroid/bluetooth/BluetoothDevice;->getName()Ljava/lang/String;
    move-result-object v0
    if-eqz v0, :cond_2
    invoke-virtual {v0}, Ljava/lang/String;->toLowerCase()Ljava/lang/String;
    move-result-object v0
    const-string v1, "remote"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "rcu"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "control"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "mouse"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "headphone"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "headset"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "earphone"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "earbud"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "buds"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "airpods"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "freebuds"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "handsfree"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "hands-free"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0
    const-string v1, "tws"
    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :cond_0

    :cond_2
    const/4 v0, 0x0
    return v0
    :cond_0
    const/4 v0, 0x1
    return v0
.end method

.method private registerPairingRequestReceiver()V
    .locals 3

    iget-boolean v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mPairingRequestReceiverRegistered:Z
    if-nez v0, :cond_0
    new-instance v0, Landroid/content/IntentFilter;
    const-string v1, "android.bluetooth.device.action.PAIRING_REQUEST"
    invoke-direct {v0, v1}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
    const/16 v1, 0x3e8
    invoke-virtual {v0, v1}, Landroid/content/IntentFilter;->setPriority(I)V
    iget-object v1, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mContext:Landroid/content/Context;
    iget-object v2, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mPairingRequestReceiver:Landroid/content/BroadcastReceiver;
    invoke-virtual {v1, v2, v0}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;
    const/4 v0, 0x1
    iput-boolean v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mPairingRequestReceiverRegistered:Z
    const-string v0, "CrownBtPairing"
    const-string v1, "registered priority=1000 pairing-request owner"
    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    :cond_0
    return-void
.end method

.method private unregisterPairingRequestReceiver()V
    .locals 2

    iget-boolean v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mPairingRequestReceiverRegistered:Z
    if-eqz v0, :cond_0
    iget-object v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mContext:Landroid/content/Context;
    iget-object v1, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mPairingRequestReceiver:Landroid/content/BroadcastReceiver;
    invoke-virtual {v0, v1}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V
    const/4 v0, 0x0
    iput-boolean v0, p0, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->mPairingRequestReceiverRegistered:Z
    const-string v0, "CrownBtPairing"
    const-string v1, "unregistered pairing-request owner"
    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    :cond_0
    return-void
.end method

'@
    $anchor=".method private startBonding()V`n"
    $pairer=Replace-Once $pairer $anchor ($pairingReceiverHelpers+$anchor)
    $oldBlock=@'
.method private onBondFailed()V
    .locals 3

    const-string v0, "BluetoothDevicePairer"
'@
    $newBlock=@'
.method private onBondFailed()V
    .locals 3

    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->unregisterPairingRequestReceiver()V
    const-string v0, "BluetoothDevicePairer"
'@
    $pairer=Replace-Once $pairer $oldBlock $newBlock
    $oldBlock=@'
.method private onBonded()V
    .locals 0

    .line 577
'@
    $newBlock=@'
.method private onBonded()V
    .locals 0

    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->unregisterPairingRequestReceiver()V
    .line 577
'@
    $pairer=Replace-Once $pairer $oldBlock $newBlock
    $oldBlock=@'
.method public dispose()V
    .locals 2

    .line 385
'@
    $newBlock=@'
.method public dispose()V
    .locals 2

    invoke-direct {p0}, Lcom/android/tv/settings/accessories/BluetoothDevicePairer;->unregisterPairingRequestReceiver()V
    .line 385
'@
    $pairer=Replace-Once $pairer $oldBlock $newBlock

    # The high-priority dynamic receiver owns the ordered pairing request for the
    # two BLE allowlist remotes, launches the TV dialog, and suppresses the duplicate
    # com.android.settings dialog that races the confirmation on this ROM.
    $pairingRequest=$originalByRelative[$pairingRequestRelative]
    $oldBlock=@'
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 7

    .line 33
'@
    $newBlock=@'
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 8

    move-object v7, p0
    .line 33
'@
    $pairingRequest=Replace-Once $pairingRequest $oldBlock $newBlock
    $oldBlock=@'
    .line 59
    invoke-virtual {p1, v5}, Landroid/content/Context;->startActivity(Landroid/content/Intent;)V

    return-void
'@
    $newBlock=@'
    .line 59
    invoke-virtual {p1, v5}, Landroid/content/Context;->startActivity(Landroid/content/Intent;)V
    invoke-virtual {v7}, Landroid/content/BroadcastReceiver;->abortBroadcast()V
    const-string p0, "CrownBtPairing"
    const-string p1, "TV pairing dialog owns ordered request; duplicate Settings dialog suppressed"
    invoke-static {p0, p1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    return-void
'@
    $pairingRequest=Replace-Once $pairingRequest $oldBlock $newBlock

    # UI: MAC title fallback for null/blank names and visible row-count logging.
    $ui=$originalByRelative[$uiRelative]
    $oldBlock=@'
.method public updateList(Ljava/util/List;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
    .locals 5
'@
    $newBlock=@'
.method public updateList(Ljava/util/List;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
    .locals 6
'@
    $ui=Replace-Once $ui $oldBlock $newBlock
    $oldBlock=@'
    .line 94
    :cond_1
    invoke-interface {p1}, Ljava/util/List;->iterator()Ljava/util/Iterator;
'@
    $newBlock=@'
    .line 94
    :cond_1
    new-instance v2, Ljava/lang/StringBuilder;
    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
    const-string v3, "UI list count="
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-interface {p1}, Ljava/util/List;->size()I
    move-result v3
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v2
    const-string v3, "CrownBtVisible"
    invoke-static {v3, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    invoke-interface {p1}, Ljava/util/List;->iterator()Ljava/util/Iterator;
'@
    $ui=Replace-Once $ui $oldBlock $newBlock
    $oldBlock=@'
    invoke-virtual {v2}, Landroid/bluetooth/BluetoothDevice;->getName()Ljava/lang/String;

    move-result-object v4

    invoke-virtual {v3, v4}, Landroidx/preference/Preference;->setTitle(Ljava/lang/CharSequence;)V
'@
    $newBlock=@'
    invoke-virtual {v2}, Landroid/bluetooth/BluetoothDevice;->getName()Ljava/lang/String;

    move-result-object v4

    if-eqz v4, :cond_20
    invoke-virtual {v4}, Ljava/lang/String;->trim()Ljava/lang/String;
    move-result-object v4
    invoke-virtual {v4}, Ljava/lang/String;->isEmpty()Z
    move-result v5
    if-eqz v5, :cond_21
    :cond_20
    invoke-virtual {v2}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
    move-result-object v4
    :cond_21
    invoke-virtual {v3, v4}, Landroidx/preference/Preference;->setTitle(Ljava/lang/CharSequence;)V
'@
    $ui=Replace-Once $ui $oldBlock $newBlock

    $patchedByRelative=@{
        $scannerRelative=$scanner
        $criteriaRelative=$criteria
        $pairerRelative=$pairer
        $pairingRequestRelative=$pairingRequest
        $uiRelative=$ui
    }
    $audit=Join-Path $work 'Patch_Audit'
    New-Item -ItemType Directory -Path $audit | Out-Null
    foreach($rel in $patchedByRelative.Keys){
        $safe=($rel -replace '[\\/:*?"<>|$]','_')
        Write-Smali (Join-Path $audit ($safe+'_Before.smali')) $originalByRelative[$rel]
        Write-Smali (Join-Path $decoded $rel) $patchedByRelative[$rel]
        Write-Smali (Join-Path $audit ($safe+'_After.smali')) $patchedByRelative[$rel]
    }
    Write-Host '[OK] V1.4.7 accessory-only list, MAC fallback, LE transport and single-owner pairing request patched.' -ForegroundColor Green
    $rebuilt=Join-Path $work 'rebuilt.apk'
    Native $java @('-jar',$tool,'b',$decoded,'-o',$rebuilt) | Out-Host
    $helper=Join-Path $work 'CrownCleanZip.java'
    $helperCode=@'
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

class CrownCleanZip {
    static final String OLD = "com.android.settings.files", NEW = "com.crown.tvsettings.files";
    static void require(boolean ok, String message) throws IOException { if (!ok) throw new IOException(message); }
    static boolean skip(String n) { return n.matches("(?i)META-INF/([^/]+\\.(SF|RSA|DSA|EC)|MANIFEST\\.MF)"); }
    static byte[] read(ZipFile z, ZipEntry e) throws IOException {
        require(e != null, "Missing ZIP entry");
        byte[] b; try (InputStream s = z.getInputStream(e)) { b = s.readAllBytes(); }
        CRC32 crc = new CRC32(); crc.update(b);
        require(b.length == e.getSize() && crc.getValue() == e.getCrc(), "CRC/size mismatch: " + e.getName());
        return b;
    }
    static void put(ZipOutputStream out, ZipEntry original, byte[] data) throws IOException {
        // Explicit STORED: no stale extra fields, descriptors, or compressed-size values.
        CRC32 crc = new CRC32(); crc.update(data);
        ZipEntry e = new ZipEntry(original.getName()); e.setMethod(ZipEntry.STORED);
        e.setSize(data.length); e.setCompressedSize(data.length); e.setCrc(crc.getValue());
        if(original.getTime()>=0) e.setTime(original.getTime());
        out.putNextEntry(e); out.write(data); out.closeEntry();
    }
    static Map<String,ZipEntry> index(ZipFile z) throws IOException {
        Map<String,ZipEntry> map=new LinkedHashMap<>();
        for(Enumeration<? extends ZipEntry> it=z.entries();it.hasMoreElements();) {
            ZipEntry e=it.nextElement(); if(skip(e.getName())) continue;
            require(map.put(e.getName(),e)==null,"Duplicate ZIP entry: "+e.getName());
        } return map;
    }
    static void build(String source,String rebuilt,String output) throws IOException {
        try(ZipFile src=new ZipFile(source); ZipFile dex=new ZipFile(rebuilt); ZipOutputStream out=new ZipOutputStream(Files.newOutputStream(Path.of(output),StandardOpenOption.CREATE_NEW))) {
            Map<String,ZipEntry> entries=index(src);
            require(entries.containsKey("AndroidManifest.xml")&&entries.containsKey("classes.dex"),"Missing original manifest/DEX");
            for(ZipEntry e:entries.values()) {
                byte[] b=read(src,e);
                
                if(e.getName().equals("classes.dex")) b=read(dex,dex.getEntry("classes.dex"));
                put(out,e,b);
            }
        }
    }
    static void verify(String source,String rebuilt,String output) throws IOException {
        try(ZipFile src=new ZipFile(source);ZipFile dex=new ZipFile(rebuilt);ZipFile result=new ZipFile(output)) {
            Map<String,ZipEntry> a=index(src), b=index(result);
            require(a.keySet().equals(b.keySet()),"Unexpected ZIP entry names");
            int changed=0;
            for(String n:a.keySet()) {
                byte[] orig=read(src,a.get(n)), actual=read(result,b.get(n)), expected=orig;
                
                if(n.equals("classes.dex")) expected=read(dex,dex.getEntry(n));
                require(Arrays.equals(actual,expected),"Unexpected entry contents: "+n);
                if(!Arrays.equals(orig,actual)) changed++;
            }
            require(changed==1,"Expected exactly one changed entry, found "+changed);
            System.out.println("[OK] ZIP CRC32, sizes and content verified: "+a.size()+" entries; only DEX changed.");
        }
    }
    public static void main(String[] args) throws Exception {
        require(args.length==4,"Usage: build|verify source rebuilt output");
        if(args[0].equals("build")) build(args[1],args[2],args[3]);
        else if(args[0].equals("verify")) verify(args[1],args[2],args[3]);
        else throw new IllegalArgumentException("Unknown mode");
    }
}

'@
    [IO.File]::WriteAllText($helper,$helperCode,[Text.UTF8Encoding]::new($false))
    $unsigned=Join-Path $work 'unsigned_clean.apk'
    Native $java @($helper,'build',$src,$rebuilt,$unsigned) | Out-Host
    Native $java @($helper,'verify',$src,$rebuilt,$unsigned) | Out-Host
    # Check unsigned APK before signing too.
    $unsignedManifest = @(Native $aapt @('dump','xmltree','--file','AndroidManifest.xml',$unsigned))
    if (($beforeManifest -join "`n") -cne ($unsignedManifest -join "`n")) { throw 'Unexpected unsigned manifest changes.' }
    $aligned=Join-Path $work 'aligned.apk'
    Native $zipalign @('-f','4',$unsigned,$aligned) | Out-Host
    $candidate=Join-Path $work 'candidate_unverified.apk'
    Native $java @('-jar',$signer,'sign','--key',$key,'--cert',$cert,'--out',$candidate,$aligned) | Out-Host
    Check-Signer $candidate
    Native $zipalign @('-c','4',$candidate) | Out-Host
    Native $java @($helper,'verify',$src,$rebuilt,$candidate) | Out-Host
    $afterManifest=@(Native $aapt @('dump','xmltree','--file','AndroidManifest.xml',$candidate))
    $afterManifest | Set-Content -LiteralPath (Join-Path $work 'Manifest_After.txt') -Encoding UTF8
    if (($beforeManifest -join "`n") -cne ($afterManifest -join "`n")) { throw 'Unexpected final manifest changes.' }
    Native $aapt @('dump','badging',$candidate) | Set-Content -LiteralPath (Join-Path $work 'Badging.txt') -Encoding UTF8
    Write-Host '[OK] AAPT2 manifest and badging; platform signature and zipalign.' -ForegroundColor Green
    $check=Join-Path $work 'verified_decoded'
    Native $java @('-jar',$tool,'d','-r','-f','-o',$check,$candidate) | Out-Host
    $requiredMarkers=@{
        $scannerRelative=@('crownScheduleScan(J)V','startDiscovery=false; retry in 2500ms','Stopped; callbacks removed, receiver unregistered','CrownBtScanFound','crownLogFound','CrownBtFilter')
        $criteriaRelative=@('crownLogDecision','invalid_address','major_class_mismatch')
        $pairerRelative=@('Pairer diagnostic matcher enabled','crownIsAccessory','hidden non-accessory address=','18:BF:1C:96:9D:76','20:0B:16:5C:13:94','forcing TRANSPORT_LE (2)','registered priority=1000 pairing-request owner','allowlisted BLE remote routed to HID connector','CrownBtVisible')
        $pairingRequestRelative=@('abortBroadcast','duplicate Settings dialog suppressed','CrownBtPairing')
        $uiRelative=@('UI list count=','CrownBtVisible')
    }
    foreach($rel in $requiredMarkers.Keys){
        $verified=Read-Smali (Join-Path $check $rel)
        if((Canonical-SmaliSorted $verified) -cne (Canonical-SmaliSorted $patchedByRelative[$rel])){throw "Final DEX semantic verification failed: $rel"}
        foreach($marker in $requiredMarkers[$rel]){
            if(!$verified.Contains($marker)){throw "Final DEX missing marker '$marker' in $rel"}
        }
    }
    # Check every smali file after rebuilding; only five targeted classes may differ from V1.4.6.
    $smaliFiles=@(Get-ChildItem -LiteralPath $decoded -Recurse -File -Filter '*.smali')
    $verifiedFiles=@(Get-ChildItem -LiteralPath $check -Recurse -File -Filter '*.smali')
    if($smaliFiles.Count -ne $verifiedFiles.Count){throw 'Unexpected smali file count.'}
    foreach($f in $smaliFiles){
        $rel=$f.FullName.Substring($decoded.Length+1)
        $other=Join-Path $check $rel
        if(!(Test-Path -LiteralPath $other -PathType Leaf)){throw "Missing final class: $rel"}
        if($patchedByRelative.ContainsKey($rel)){
            if((Canonical-SmaliSorted (Read-Smali $f.FullName)) -cne (Canonical-SmaliSorted (Read-Smali $other))){throw "Unexpected rebuilt change: $rel"}
        } elseif((Read-Smali $f.FullName) -cne (Read-Smali $other)){throw "Unexpected smali change: $rel"}
    }
    Write-Host "[OK] All $($smaliFiles.Count) smali files verified; exactly five targeted classes changed and all V1.4.6 fixes retained." -ForegroundColor Green
    $final=Join-Path $work 'CrownTvSettings_TouchEdition_V1_4_7.apk'
    Move-Item -LiteralPath $candidate -Destination $final
    Write-Host 'BUILD_OK: V1.4.7 accessory-only visible list, LE transport and single-dialog BLE pairing; original manifest/resources unchanged.' -ForegroundColor Green
    Get-FileHash -LiteralPath $final -Algorithm SHA256 | Format-List
    Write-Host "CANDIDATE: $final"
    Write-Host 'Build only. No device changes. Test as APK update before system integration.'
} finally { Stop-Transcript | Out-Null }
