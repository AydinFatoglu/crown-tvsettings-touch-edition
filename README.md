# Crown TvSettings Touch Edition

Reproducible PowerShell build pipeline for **Crown TvSettings Touch Edition v1.4.7**. It applies a narrowly scoped Bluetooth accessory discovery and pairing patch to the verified v1.4.6 APK, rebuilds only the application DEX, signs the result with the supplied platform key, and performs extensive integrity checks before producing a candidate APK.

> [!IMPORTANT]
> The Git source tree contains the build script only. It does not include Crown firmware, Android platform keys, or Apktool. An authorized prebuilt APK is available separately on the Releases page. Use it only with devices and software you are authorized to modify.

## Download

The verified v1.4.7 APK is available from the [latest GitHub release](https://github.com/AydinFatoglu/crown-tvsettings-touch-edition/releases/latest).

```text
SHA-256: F9187D4B9AE64DDA4F0676C80E0EE81AA88B6354B548E5FA789E35D167E44C57
```

The release APK is platform-signed for the inspected Crown firmware lineage. Test it as an APK update before considering system-image integration.

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

The pipeline is designed to stop rather than produce an unverified build:

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

The script performs **no ADB commands and no device or system writes**. It only creates a candidate APK. Test that APK as an update before considering any system-image integration.

## Requirements

- Windows with PowerShell 7 recommended.
- Android Studio's bundled Java runtime at:
  `C:\Program Files\Android\Android Studio\jbr\bin\java.exe`
- Android SDK Build Tools `37.0.0`, including `aapt2.exe`, `zipalign.exe`, and `lib\apksigner.jar`.
- Apktool `2.11.1` with the SHA-256 expected by the script.
- The exact v1.4.6 Touch Edition APK expected by the script.
- Matching Android platform signing key and X.509 certificate.

Paths and expected hashes are deliberately pinned near the top of the script. If your authorized environment uses different tool locations or source artifacts, review those values explicitly instead of bypassing the checks.

## Expected input layout

Pass a build root with the following structure:

```text
Crown_TvSettings_Extract/
|-- apktool_2.11.1.jar
|-- PlatformKeys/
|   |-- platform.pk8
|   `-- platform.x509.pem
`-- TouchFix_V1_4_6_20261127_011623/
    `-- CrownTvSettings_TouchEdition_V1_4_6.apk
```

The default root is `%USERPROFILE%\Downloads\Crown_TvSettings_Extract`.

## Build

From PowerShell:

```powershell
pwsh -File .\Build_Crown_TvSettings_TouchEdition_V1_4_7.ps1 `
  -Root "$env:USERPROFILE\Downloads\Crown_TvSettings_Extract"
```

On success, the script prints `BUILD_OK`, the final APK path, and its SHA-256 hash. A timestamped directory named `TouchFix_V1_4_7_yyyyMMdd_HHmmss` is created under the build root.

## Build output

The timestamped directory contains:

- `CrownTvSettings_TouchEdition_V1_4_7.apk` — signed and verified candidate APK.
- `Build_Log.txt` — complete PowerShell transcript.
- `Patch_Audit/` — before-and-after Smali for each targeted class.
- `Manifest_Before.txt` and `Manifest_After.txt` — manifest inspection evidence.
- `Badging.txt` — final `aapt2 dump badging` output.
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
|-- README.md
`-- .gitignore
```

## Scope

This is a version-pinned maintenance build, not a general-purpose APK patcher. Its exact hashes, Smali anchors, target classes, signer identity, and device allowlist are intentional safeguards for one inspected Crown TvSettings lineage. A different base APK should be analyzed and supported as a separate version rather than forced through this pipeline.
