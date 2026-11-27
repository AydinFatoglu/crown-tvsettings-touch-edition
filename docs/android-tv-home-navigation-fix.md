# Android TV HOME and Touch Navigation Fix

This document covers a device-level Android configuration issue observed during physical testing on an Amazon Echo Show 8 Gen 1 (`crown`) running LineageOS 18.1 / Android 11 with Android TV mode enabled.

It is separate from the Crown TvSettings Touch Edition v1.4.7 APK patch. The APK patch addresses Bluetooth accessory discovery and pairing; the setting below restores normal HOME and touch-navigation behavior after Android TV mode is configured.

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

> [!NOTE]
> Persistence after a full device reboot has not yet been tested. Do not assume reboot persistence until it is confirmed on the target device.

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

The user confirmed that navigation returned to its previous normal behavior. Reboot persistence remains untested.

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
