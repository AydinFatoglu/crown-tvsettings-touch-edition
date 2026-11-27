# Crown TvSettings Touch Edition

Reproducible PowerShell build pipelines for **Crown TvSettings Touch Edition v1.4.8**. The v1.4.7 pipeline applies a narrowly scoped Bluetooth accessory discovery and pairing patch; v1.4.8 preserves that verified DEX and disables the duplicate TV fallback HOME component that caused a reboot-time resolver loop. Both builders sign and extensively verify their candidate APKs.

> [!IMPORTANT]
> The Git source tree contains the build scripts only. It does not include Crown firmware, Android platform keys, ROM frameworks, or Apktool. An authorized prebuilt APK is available separately on the Releases page. Use it only with devices and software you are authorized to modify.

## Download

The verified v1.4.8 APK is available from the [latest GitHub release](https://github.com/AydinFatoglu/crown-tvsettings-touch-edition/releases/latest).

```text
SHA-256: DB2C83D763EBE1756B6D4CDA564BD1AF7724A09E066B2A7C609B41D20C799E82
```

The release APK is platform-signed for the inspected Crown firmware lineage. v1.4.8 completed a controlled physical-device reboot test with the temporary component override reset to its default state.

> [!WARNING]
> **Archived v1.4.7 reboot issue:** v1.4.7 registers a second fallback HOME activity alongside the standard Android Settings fallback. On the tested device this caused a pre-unlock `ResolverActivity` loop, leaving the device at the Android boot logo after reboot. Use v1.4.8 instead. See [Android TV HOME and Touch Navigation Fix](docs/android-tv-home-navigation-fix.md#v147-reboot-time-boot-stall) for diagnosis and recovery. The v1.4.7 release is retained unchanged for traceability and should not be treated as reboot-safe.

## Troubleshooting

### Android TV HOME and touch navigation

On the tested Amazon Echo Show 8 Gen 1 (`crown`) configuration, enabling Android TV mode requires one device-level post-configuration step so WindowManager recognizes TV user setup as complete:

```shell
adb shell settings --user 0 put secure tv_user_setup_complete 1
```

Without this flag, HOME and touch navigation may fail even when the normal Android setup flags and launcher configuration are correct. See [Android TV HOME and Touch Navigation Fix](docs/android-tv-home-navigation-fix.md) for symptoms, diagnosis, Logcat evidence, verification, physical-device results, and rollback instructions.

This device setting is separate from the Crown TvSettings Touch Edition Bluetooth APK patch. The value persisted through a full reboot on the tested device. That reboot also exposed a separate v1.4.7 duplicate fallback-HOME boot issue documented in the linked guide.

## What v1.4.8 changes

- Retains the verified v1.4.7 DEX, resources, Bluetooth behavior, package identity, and signer.
- Disables only `com.android.tv.settings.system.FallbackHome` in the APK manifest.
- Leaves the standard `com.android.settings/.FallbackHome` available during pre-unlock boot.
- Allows QuickstepLauncher to become HOME after user unlock without a resolver loop.
- Completed a controlled reboot with user 0 `RUNNING_UNLOCKED`, boot animation stopped, Android TV mode `0x24`, and HOME focused on QuickstepLauncher.

An independent ZIP-content comparison confirmed that `AndroidManifest.xml` is the only APK entry whose content differs from v1.4.7.

## What v1.4.7 changes

- Shows accessory devices instead of every nearby Bluetooth device.
- Validates Bluetooth addresses and tolerates devices with missing or unknown Class of Device metadata.
- Falls back to the MAC address when a device name is missing or blank.
- Deduplicates discovered and visible devices by address.
- Keeps manual device selection mandatory; discovery does not trigger automatic pairing.
- Routes the two configured BLE HID remotes through the LE transport and HID connector.
- Uses one high-priority pairing-request owner for allowlisted remotes, preventing the duplicate Settings pairing dialog seen on the target ROM.
- Adds focused diagnostic logging for scanning, filtering, visibility, and pairing.

The two known remote addresses are intentionally embedded in the patch logic. Review the `crownIsAccessory` and pairing-request sections before using this build for different hardware.

## Safety and reproducibility

The pipelines are designed to stop rather than produce an unverified build:

- Verifies the SHA-256 hashes of the v1.4.6 source APK and Apktool.
- Confirms the source APK signer certificate and provider authority.
- Requires every Smali patch anchor and target method to be unique.
- Restricts changes to five Bluetooth-related classes.
- Rebuilds the archive so that `classes.dex` is the only changed APK entry.
- Checks ZIP entry names, CRC32 values, sizes, and contents.
- Confirms that the manifest is byte-for-byte equivalent before and after the build.
- Runs `zipalign` validation and APK signature verification.
- Decodes the final APK again and semantically compares every Smali file.
- Produces patch-audit copies of the five classes before and after modification.
- Hash-pins the exact v1.4.7 source and the Android and LineageOS resource frameworks used for v1.4.8.
- Restricts v1.4.8 to one changed archive entry: `AndroidManifest.xml`.
- Semantically verifies that the only manifest change is `android:enabled="false"` on the duplicate TV fallback HOME activity.

The build scripts perform **no ADB commands and no device or system writes**. They only create candidate APKs.

## Requirements

- Windows with PowerShell 7 recommended.
- Android Studio's bundled Java runtime at:
  `C:\Program Files\Android\Android Studio\jbr\bin\java.exe`
- Android SDK Build Tools `37.0.0`, including `aapt2.exe`, `zipalign.exe`, and `lib\apksigner.jar`.
- Apktool `2.11.1` with the SHA-256 expected by the script.
- The exact source APK expected by the selected versioned builder.
- For v1.4.8, the hash-pinned `framework-res.apk` and `org.lineageos.platform-res.apk` from the tested Crown LineageOS build.
- Matching Android platform signing key and X.509 certificate.

Paths and expected hashes are deliberately pinned near the top of the script. If your authorized environment uses different tool locations or source artifacts, review those values explicitly instead of bypassing the checks.

## Expected input layout

Pass a build root with the following structure:

```text
Crown_TvSettings_Extract/
|-- apktool_2.11.1.jar
|-- Frameworks/
|   |-- framework-res.apk
|   `-- org.lineageos.platform-res.apk
|-- PlatformKeys/
|   |-- platform.pk8
|   `-- platform.x509.pem
|-- TouchFix_V1_4_6_20261127_011623/
|   `-- CrownTvSettings_TouchEdition_V1_4_6.apk
`-- TouchFix_V1_4_7_20261127_023901/
    `-- CrownTvSettings_TouchEdition_V1_4_7.apk
```

The default root is `%USERPROFILE%\Downloads\Crown_TvSettings_Extract`.

## Build

From PowerShell:

```powershell
pwsh -File .\Build_Crown_TvSettings_TouchEdition_V1_4_7.ps1 `
  -Root "$env:USERPROFILE\Downloads\Crown_TvSettings_Extract"

pwsh -File .\Build_Crown_TvSettings_TouchEdition_V1_4_8.ps1 `
  -Root "$env:USERPROFILE\Downloads\Crown_TvSettings_Extract"
```

Build v1.4.7 first when starting from the v1.4.6 input, then use that exact verified output as the v1.4.8 input. On success, each script prints `BUILD_OK`, the final APK path, and its SHA-256 hash in a versioned timestamped directory.

## Build output

The timestamped directory contains:

- `CrownTvSettings_TouchEdition_V1_4_8.apk` — signed and verified latest candidate APK.
- `Build_Log.txt` — complete PowerShell transcript.
- `Patch_Audit/` — v1.4.7 before-and-after Smali for each targeted class.
- `Manifest_Before.txt` and `Manifest_After.txt` — manifest inspection evidence.
- `Badging_Before.txt` and `Badging_After.txt` — v1.4.8 package metadata evidence.
- Decoded and intermediate build material used by the verification stages.

## Diagnostic tags

Useful Android log tags added or checked by the patch include:

```text
CrownBtScan
CrownBtScanFound
CrownBtFilter
CrownBtVisible
CrownBtPairing
```

These tags help trace discovery decisions, visible-list updates, LE routing, and pairing-dialog ownership during device testing.

## Repository contents

```text
.
|-- Build_Crown_TvSettings_TouchEdition_V1_4_7.ps1
|-- Build_Crown_TvSettings_TouchEdition_V1_4_8.ps1
|-- docs/
|   `-- android-tv-home-navigation-fix.md
|-- README.md
`-- .gitignore
```

## Scope

These are version-pinned maintenance builds, not general-purpose APK patchers. Their exact hashes, framework inputs, Smali anchors, target classes, signer identity, manifest constraint, and device allowlist are intentional safeguards for one inspected Crown TvSettings lineage. A different base APK or ROM framework should be analyzed and supported as a separate version rather than forced through these pipelines.
