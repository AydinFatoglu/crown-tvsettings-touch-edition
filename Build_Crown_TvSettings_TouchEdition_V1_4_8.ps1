# Crown TvSettings V1.4.8 Touch Edition - disable the duplicate TV fallback HOME; clean manifest-only APK rebuild; no ADB or system writes.
param(
    [string]$Root = "$env:USERPROFILE\Downloads\Crown_TvSettings_Extract",
    [string]$SourceApk = ''
)

$ErrorActionPreference = 'Stop'
if (!$SourceApk) {
    $SourceApk = Join-Path $Root 'TouchFix_V1_4_7_20261127_023901\CrownTvSettings_TouchEdition_V1_4_7.apk'
}

$work = Join-Path $Root ('TouchFix_V1_4_8_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$java = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
$sdk = "$env:LOCALAPPDATA\Android\Sdk\build-tools\37.0.0"
$signer = Join-Path $sdk 'lib\apksigner.jar'
$zipalign = Join-Path $sdk 'zipalign.exe'
$aapt = Join-Path $sdk 'aapt2.exe'
$key = Join-Path $Root 'PlatformKeys\platform.pk8'
$cert = Join-Path $Root 'PlatformKeys\platform.x509.pem'
$tool = Join-Path $Root 'apktool_2.11.1.jar'
$androidFramework = Join-Path $Root 'Frameworks\framework-res.apk'
$lineageFramework = Join-Path $Root 'Frameworks\org.lineageos.platform-res.apk'
$expectedSource = 'F9187D4B9AE64DDA4F0676C80E0EE81AA88B6354B548E5FA789E35D167E44C57'
$expectedSigner = 'c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8'
$expectedTool = '56D59C524FC764263BA8D345754D8DAF55B1887818B15CD3B594F555D249E2DB'
$expectedAndroidFramework = '31C5C9CA31AF991CFBA36FA24B4148831F0143C856301F289A9FFBC1322A7B7D'
$expectedLineageFramework = '6466FCB70F8E685F20D563DFFEBC541F0F4E184B21CD6CFCF406DFF97F451FB7'
$androidNs = 'http://schemas.android.com/apk/res/android'
$fallbackClass = 'com.android.tv.settings.system.FallbackHome'

function Native([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $lines = @(& $Exe @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        $lines | Out-Host
        throw "Exit $rc from $Exe"
    }
    $lines
}

function Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Check-Signer([string]$Path) {
    $verification = @(Native $java @('-jar', $signer, 'verify', '--verbose', '--print-certs', $Path))
    if (($verification -join "`n") -notmatch [regex]::Escape($expectedSigner)) {
        throw 'Platform signature mismatch.'
    }
    $verification | Out-Host
}

function Load-Manifest([string]$Path) {
    $document = [Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $false
    $document.Load($Path)
    $document
}

function Get-FallbackNode([Xml.XmlDocument]$Document) {
    $namespaces = [Xml.XmlNamespaceManager]::new($Document.NameTable)
    $namespaces.AddNamespace('android', $androidNs)
    $nodes = @($Document.SelectNodes("/manifest/application/activity[@android:name='$fallbackClass']", $namespaces))
    if ($nodes.Count -ne 1) {
        throw "Expected exactly one $fallbackClass activity; found $($nodes.Count)."
    }
    $nodes[0]
}

function Add-CanonicalXmlNode([Xml.XmlNode]$Node, [Text.StringBuilder]$Builder) {
    if ($Node.NodeType -eq [Xml.XmlNodeType]::Element) {
        [void]$Builder.Append('<{').Append($Node.NamespaceURI).Append('}').Append($Node.LocalName)
        $attributes = @($Node.Attributes | Where-Object {
            $_.NamespaceURI -ne 'http://www.w3.org/2000/xmlns/'
        } | Sort-Object NamespaceURI, LocalName)
        foreach ($attribute in $attributes) {
            [void]$Builder.Append(' {').Append($attribute.NamespaceURI).Append('}').Append($attribute.LocalName)
            [void]$Builder.Append('="').Append([Security.SecurityElement]::Escape($attribute.Value)).Append('"')
        }
        [void]$Builder.Append('>')
        foreach ($child in $Node.ChildNodes) {
            if ($child.NodeType -eq [Xml.XmlNodeType]::Element) {
                Add-CanonicalXmlNode $child $Builder
            } elseif ($child.NodeType -in @([Xml.XmlNodeType]::Text, [Xml.XmlNodeType]::CDATA)) {
                $value = $child.Value.Trim()
                if ($value) {
                    [void]$Builder.Append([Security.SecurityElement]::Escape($value))
                }
            }
        }
        [void]$Builder.Append('</{').Append($Node.NamespaceURI).Append('}').Append($Node.LocalName).Append('>')
    }
}

function Canonical-Manifest([Xml.XmlDocument]$Document) {
    $builder = [Text.StringBuilder]::new()
    Add-CanonicalXmlNode $Document.DocumentElement $builder
    $builder.ToString()
}

function Save-Manifest([Xml.XmlDocument]$Document, [string]$Path) {
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $settings.NewLineChars = "`n"
    $settings.NewLineHandling = [Xml.NewLineHandling]::Replace
    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Document.Save($writer)
    } finally {
        $writer.Dispose()
    }
}

foreach ($path in @($SourceApk, $java, $signer, $zipalign, $aapt, $tool, $key, $cert, $androidFramework, $lineageFramework)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing: $path"
    }
}
if ((Sha $SourceApk) -ne $expectedSource) {
    throw 'V1.4.7 APK SHA256 mismatch.'
}
if ((Sha $tool) -ne $expectedTool) {
    throw 'Apktool SHA256 mismatch.'
}
if ((Sha $androidFramework) -ne $expectedAndroidFramework) {
    throw 'Android framework-res.apk SHA256 mismatch.'
}
if ((Sha $lineageFramework) -ne $expectedLineageFramework) {
    throw 'LineageOS platform resource APK SHA256 mismatch.'
}

New-Item -ItemType Directory -Path $work | Out-Null
Start-Transcript -Path (Join-Path $work 'Build_Log.txt') | Out-Null
try {
    Check-Signer $SourceApk
    $beforeManifestDump = @(Native $aapt @('dump', 'xmltree', '--file', 'AndroidManifest.xml', $SourceApk))
    $beforeManifestDump | Set-Content -LiteralPath (Join-Path $work 'Manifest_Before.txt') -Encoding UTF8
    $beforeBadging = @(Native $aapt @('dump', 'badging', $SourceApk))
    $beforeBadging | Set-Content -LiteralPath (Join-Path $work 'Badging_Before.txt') -Encoding UTF8
    Write-Host '[OK] V1.4.7 source hash, platform signature, manifest and badging verified.' -ForegroundColor Green

    $frameworkCache = Join-Path $work 'framework'
    New-Item -ItemType Directory -Path $frameworkCache | Out-Null
    Native $java @('-jar', $tool, 'if', '-p', $frameworkCache, $androidFramework) | Out-Host
    Native $java @('-jar', $tool, 'if', '-p', $frameworkCache, $lineageFramework) | Out-Host
    Write-Host '[OK] Hash-pinned Android and LineageOS resource frameworks installed in the isolated build cache.' -ForegroundColor Green

    $decoded = Join-Path $work 'decoded'
    Native $java @('-jar', $tool, 'd', '-p', $frameworkCache, '-f', '-o', $decoded, $SourceApk) | Out-Host
    $manifestPath = Join-Path $decoded 'AndroidManifest.xml'
    $sourceManifest = Load-Manifest $manifestPath
    $sourceFallback = Get-FallbackNode $sourceManifest
    $sourceEnabled = $sourceFallback.GetAttribute('enabled', $androidNs)
    if ($sourceEnabled -and $sourceEnabled -ne 'true') {
        throw "Unexpected source FallbackHome enabled state: '$sourceEnabled'."
    }

    $expectedManifest = [Xml.XmlDocument]$sourceManifest.CloneNode($true)
    $expectedFallback = Get-FallbackNode $expectedManifest
    $enabledAttribute = $expectedManifest.CreateAttribute('android', 'enabled', $androidNs)
    $enabledAttribute.Value = 'false'
    [void]$expectedFallback.Attributes.Append($enabledAttribute)
    $expectedCanonical = Canonical-Manifest $expectedManifest
    Save-Manifest $expectedManifest $manifestPath
    Write-Host '[OK] Duplicate TV FallbackHome set to android:enabled=false in the decoded manifest.' -ForegroundColor Green

    $rebuilt = Join-Path $work 'rebuilt.apk'
    Native $java @('-jar', $tool, 'b', '-p', $frameworkCache, $decoded, '-o', $rebuilt) | Out-Host

    $helper = Join-Path $work 'CrownManifestZip.java'
    $helperCode = @'
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

class CrownManifestZip {
    static final String MANIFEST = "AndroidManifest.xml";
    static void require(boolean ok, String message) throws IOException { if (!ok) throw new IOException(message); }
    static boolean skip(String n) { return n.matches("(?i)META-INF/([^/]+\\.(SF|RSA|DSA|EC)|MANIFEST\\.MF)"); }
    static byte[] read(ZipFile z, ZipEntry e) throws IOException {
        require(e != null, "Missing ZIP entry");
        byte[] b;
        try (InputStream s = z.getInputStream(e)) { b = s.readAllBytes(); }
        CRC32 crc = new CRC32(); crc.update(b);
        require(b.length == e.getSize() && crc.getValue() == e.getCrc(), "CRC/size mismatch: " + e.getName());
        return b;
    }
    static void put(ZipOutputStream out, ZipEntry original, byte[] data) throws IOException {
        CRC32 crc = new CRC32(); crc.update(data);
        ZipEntry e = new ZipEntry(original.getName());
        e.setMethod(ZipEntry.STORED);
        e.setSize(data.length); e.setCompressedSize(data.length); e.setCrc(crc.getValue());
        if (original.getTime() >= 0) e.setTime(original.getTime());
        out.putNextEntry(e); out.write(data); out.closeEntry();
    }
    static Map<String,ZipEntry> index(ZipFile z) throws IOException {
        Map<String,ZipEntry> map = new LinkedHashMap<>();
        for (Enumeration<? extends ZipEntry> it = z.entries(); it.hasMoreElements();) {
            ZipEntry e = it.nextElement();
            if (skip(e.getName())) continue;
            require(map.put(e.getName(), e) == null, "Duplicate ZIP entry: " + e.getName());
        }
        return map;
    }
    static void build(String source, String rebuilt, String output) throws IOException {
        try (ZipFile src = new ZipFile(source);
             ZipFile patch = new ZipFile(rebuilt);
             ZipOutputStream out = new ZipOutputStream(Files.newOutputStream(Path.of(output), StandardOpenOption.CREATE_NEW))) {
            Map<String,ZipEntry> entries = index(src);
            require(entries.containsKey(MANIFEST) && entries.containsKey("classes.dex"), "Missing original manifest/DEX");
            byte[] replacement = read(patch, patch.getEntry(MANIFEST));
            for (ZipEntry e : entries.values()) {
                byte[] data = e.getName().equals(MANIFEST) ? replacement : read(src, e);
                put(out, e, data);
            }
        }
    }
    static void verify(String source, String rebuilt, String output) throws IOException {
        try (ZipFile src = new ZipFile(source); ZipFile patch = new ZipFile(rebuilt); ZipFile result = new ZipFile(output)) {
            Map<String,ZipEntry> original = index(src), actual = index(result);
            require(original.keySet().equals(actual.keySet()), "Unexpected ZIP entry names");
            byte[] rebuiltManifest = read(patch, patch.getEntry(MANIFEST));
            int changed = 0;
            for (String name : original.keySet()) {
                byte[] before = read(src, original.get(name));
                byte[] after = read(result, actual.get(name));
                byte[] expected = name.equals(MANIFEST) ? rebuiltManifest : before;
                require(Arrays.equals(after, expected), "Unexpected entry contents: " + name);
                if (!Arrays.equals(before, after)) changed++;
            }
            require(changed == 1, "Expected exactly one changed entry, found " + changed);
            System.out.println("[OK] ZIP CRC32, sizes and contents verified: " + original.size() + " entries; only AndroidManifest.xml changed.");
        }
    }
    public static void main(String[] args) throws Exception {
        require(args.length == 4, "Usage: build|verify source rebuilt output");
        if (args[0].equals("build")) build(args[1], args[2], args[3]);
        else if (args[0].equals("verify")) verify(args[1], args[2], args[3]);
        else throw new IllegalArgumentException("Unknown mode");
    }
}
'@
    [IO.File]::WriteAllText($helper, $helperCode, [Text.UTF8Encoding]::new($false))

    $unsigned = Join-Path $work 'unsigned_clean.apk'
    Native $java @($helper, 'build', $SourceApk, $rebuilt, $unsigned) | Out-Host
    Native $java @($helper, 'verify', $SourceApk, $rebuilt, $unsigned) | Out-Host

    $aligned = Join-Path $work 'aligned.apk'
    Native $zipalign @('-f', '4', $unsigned, $aligned) | Out-Host
    $candidate = Join-Path $work 'candidate_unverified.apk'
    Native $java @('-jar', $signer, 'sign', '--key', $key, '--cert', $cert, '--out', $candidate, $aligned) | Out-Host
    Check-Signer $candidate
    Native $zipalign @('-c', '4', $candidate) | Out-Host
    Native $java @($helper, 'verify', $SourceApk, $rebuilt, $candidate) | Out-Host

    $afterManifestDump = @(Native $aapt @('dump', 'xmltree', '--file', 'AndroidManifest.xml', $candidate))
    $afterManifestDump | Set-Content -LiteralPath (Join-Path $work 'Manifest_After.txt') -Encoding UTF8
    $afterBadging = @(Native $aapt @('dump', 'badging', $candidate))
    $afterBadging | Set-Content -LiteralPath (Join-Path $work 'Badging_After.txt') -Encoding UTF8
    if (($beforeBadging -join "`n") -cne ($afterBadging -join "`n")) {
        throw 'Unexpected AAPT badging changes.'
    }

    $verified = Join-Path $work 'verified_decoded'
    Native $java @('-jar', $tool, 'd', '-p', $frameworkCache, '-f', '-o', $verified, $candidate) | Out-Host
    $verifiedManifest = Load-Manifest (Join-Path $verified 'AndroidManifest.xml')
    $verifiedFallback = Get-FallbackNode $verifiedManifest
    if ($verifiedFallback.GetAttribute('enabled', $androidNs) -ne 'false') {
        throw 'Final APK does not disable the duplicate TV FallbackHome.'
    }
    if ((Canonical-Manifest $verifiedManifest) -cne $expectedCanonical) {
        throw 'Final manifest semantic verification failed; a change other than android:enabled=false was detected.'
    }
    Write-Host '[OK] Final semantic manifest differs only by android:enabled=false on the duplicate TV FallbackHome.' -ForegroundColor Green

    $final = Join-Path $work 'CrownTvSettings_TouchEdition_V1_4_8.apk'
    Move-Item -LiteralPath $candidate -Destination $final
    Write-Host 'BUILD_OK: V1.4.8 retains the verified V1.4.7 DEX/resources and disables only the duplicate TV FallbackHome manifest component.' -ForegroundColor Green
    Get-FileHash -LiteralPath $final -Algorithm SHA256 | Format-List
    Write-Host "CANDIDATE: $final"
    Write-Host 'Build only. No ADB or device changes. Install and complete a controlled reboot test before release.'
} finally {
    Stop-Transcript | Out-Null
}
