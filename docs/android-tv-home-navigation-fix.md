# Android TV HOME and Touch Navigation Fix

This document covers a device-level Android configuration issue observed during physical testing on an Amazon Echo Show 8 Gen 1 (`crown`) running LineageOS 18.1 / Android 11 with Android TV mode enabled.

It is separate from the Crown TvSettings Touch Edition Bluetooth APK patch. The APK patch addresses Bluetooth accessory discovery and pairing; the setting below restores normal HOME and touch-navigation behavior after Android TV mode is configured.

A later full-reboot test confirmed that the setup-completion setting persists. That test also exposed a separate v1.4.7 boot issue caused by two fallback HOME components. Both findings are documented below.

## Symptoms

After Android TV mode was enabled, some applications could no longer be exited through normal touch navigation gestures.

- BACK displayed the application's normal exit dialog.
- HOME did not return to the launcher.
- Starting the HOME intent directly did return to the launcher.
- Switching between gesture navigation and three-button navigation did not help.
- The configured launcher continued to function when started directly.

## Tested environment

- Device: Amazon Echo Show 8 Gen 1 (`crown`)
- Operating system: LineageOS 18.1 / Android 11
- Launcher: QuickstepLauncher
- Android TV UI mode: active (`mCurUiMode=0x24`)
- LockTask mode: `NONE`
- Accessibility services: disabled during diagnosis

No device serial number or other device-specific identifier is required for this procedure.

## Diagnosis

Confirm the different behavior of BACK and HOME:

```shell
adb shell input keyevent 4
adb shell input keyevent 3
```

Confirm that Android can start the configured HOME activity directly:

```shell
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
```

Inspect the standard and TV-specific setup flags:

```shell
adb shell settings --user 0 get secure user_setup_complete
adb shell settings get global device_provisioned
adb shell settings --user 0 get secure tv_user_setup_complete
```

The affected device reported:

```ini
user_setup_complete=1
device_provisioned=1
tv_user_setup_complete=null
```

Capture WindowManager messages while pressing HOME:

```shell
adb logcat -s WindowManager:I
```

The decisive Logcat message was:

```text
I/WindowManager: Not going home because user setup is in progress.
```

Additional checks confirmed that QuickstepLauncher was the default launcher, LockTask mode was `NONE`, accessibility services were disabled, and changing the system navigation mode did not resolve the problem. These findings ruled out launcher selection, kiosk mode, accessibility interception, and the gesture implementation as the cause.

## Root cause

Enabling Android TV mode activated Android's TV-specific setup gate. The standard setup flags were already complete, but `tv_user_setup_complete` was missing. WindowManager therefore treated TV user setup as still in progress and blocked normal HOME navigation.

## Required post-configuration step

For the tested Crown Android TV mode configuration, set the TV-specific setup-completion flag after enabling Android TV mode:

```shell
adb shell settings --user 0 put secure tv_user_setup_complete 1
```

This is a device setting, not an APK modification. It does not change the Crown TvSettings Touch Edition v1.4.7 build, Bluetooth patch logic, launcher package, or navigation mode.

No reboot was required during the verified physical-device test.

The value remained `1` after a subsequent full reboot on the tested device.

## Verification

Read the setting back and test HOME:

```shell
adb shell settings --user 0 get secure tv_user_setup_complete
adb shell input keyevent 3
```

The expected setting value is:

```text
1
```

Also retest touch navigation and exit the applications that previously remained trapped in the foreground.

## Confirmed physical-device results

- HOME key navigation: **PASS**
- Touch gesture navigation: **PASS**
- Exiting previously affected applications: **PASS**
- Launcher functionality: **PASS**
- Android TV mode preserved: **PASS**
- Accessibility reactivation required: **NO**
- Device reboot required: **NO**

The user confirmed that navigation returned to its previous normal behavior. The setting later remained `1` through a full reboot.

## v1.4.7 reboot-time boot stall

### Symptoms

After installing v1.4.7 and rebooting, the tested device remained at the Android boot logo even though ADB was available and core Android services were running.

### Diagnostic evidence

The framework had not completed boot:

```ini
sys.boot_completed=
service.bootanim.exit=0
init.svc.bootanim=running
user_0_state=BOOTING
```

The TV setup-completion setting had persisted:

```ini
tv_user_setup_complete=1
```

HOME resolution returned the framework resolver instead of a launcher. Two fallback HOME activities were eligible with the same priority:

```text
com.android.settings/.FallbackHome
com.android.tv.settings/.system.FallbackHome
```

Logcat showed a rapid `ResolverActivity` loop attempting to start Quickstep before user 0 had completed boot:

```text
ActivityNotFoundException: Unable to find explicit activity class
{com.android.launcher3/com.android.launcher3.uioverrides.QuickstepLauncher}
```

### Root cause

The standard Android Settings package and Crown TvSettings v1.4.7 both registered a fallback HOME activity. During the pre-unlock boot phase, Android could not resolve a single fallback HOME target. The resulting resolver loop prevented user 0 from leaving `BOOTING`, so the boot animation never exited.

This issue is independent of `tv_user_setup_complete` and the Bluetooth DEX patch. It comes from the v1.4.7 APK manifest retaining `com.android.tv.settings.system.FallbackHome` as an enabled HOME handler.

### Recovery for v1.4.7

The tested LineageOS build is a userdebug build and permits root ADB. Disable only the duplicate TV fallback component:

```shell
adb root
adb wait-for-device
adb shell pm disable --user 0 com.android.tv.settings/.system.FallbackHome
```

On the tested device, HOME resolution immediately reduced to the single standard Android fallback. Within seconds, user 0 became `RUNNING_UNLOCKED`, the boot animation stopped, and QuickstepLauncher became the resolved HOME activity.

Verify recovery:

```shell
adb shell getprop sys.boot_completed
adb shell getprop init.svc.bootanim
adb shell cmd package resolve-activity --brief --user 0 \
  -a android.intent.action.MAIN -c android.intent.category.HOME
adb shell input keyevent 3
```

Expected results include:

```text
1
stopped
com.android.launcher3/.uioverrides.QuickstepLauncher
```

Return ADB to normal shell mode after recovery:

```shell
adb unroot
adb wait-for-device
```

> [!WARNING]
> Do not use `pm enable` on `com.android.tv.settings/.system.FallbackHome` while v1.4.7 is installed unless intentionally reproducing the issue for controlled testing. Re-enabling the duplicate component can restore the boot-time HOME conflict.

### Permanent correction

The permanent correction is to ship Crown TvSettings with `com.android.tv.settings.system.FallbackHome` disabled in the manifest. This preserves the normal Android Settings fallback during pre-unlock boot and allows QuickstepLauncher to take over after user unlock.

This correction is implemented in v1.4.8. The v1.4.7 binary remains unchanged for traceability.

### Confirmed v1.4.8 reboot results

The v1.4.8 candidate was installed on the physical Crown device. The temporary package-manager override used for v1.4.7 recovery was reset to `default` before reboot, ensuring that the APK manifest alone controlled the component state.

- Installed APK SHA-256 matched the verified v1.4.8 candidate: **PASS**
- TV fallback absent with component override at `default`: **PASS**
- Full device reboot: **PASS**
- User 0 state `RUNNING_UNLOCKED`: **PASS**
- `sys.boot_completed=1`: **PASS**
- Boot animation stopped: **PASS**
- Quickstep `ActivityNotFoundException` regression count: **0**
- HOME resolved to QuickstepLauncher: **PASS**
- HOME key focused QuickstepLauncher: **PASS**
- Android TV mode remained `mCurUiMode=0x24`: **PASS**
- `tv_user_setup_complete=1` persisted: **PASS**

The v1.4.8 APK SHA-256 is:

```text
DB2C83D763EBE1756B6D4CDA564BD1AF7724A09E066B2A7C609B41D20C799E82
```

## Rollback

Remove the TV-specific setup-completion flag with:

```shell
adb shell settings --user 0 delete secure tv_user_setup_complete
```

> [!WARNING]
> Rolling back this setting may reproduce the original behavior in which WindowManager blocks HOME navigation because it considers TV user setup incomplete.

After rollback, read the setting again to confirm its removal:

```shell
adb shell settings --user 0 get secure tv_user_setup_complete
```
