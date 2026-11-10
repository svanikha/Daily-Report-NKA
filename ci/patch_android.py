"""Menyesuaikan folder android/ hasil `flutter create` untuk Daily Report NKA.

- Nama aplikasi, izin (internet, notifikasi, kontak), receiver notifikasi terjadwal
- <queries> untuk WhatsApp, WhatsApp Business, telepon, dan link
- Core library desugaring (dibutuhkan flutter_local_notifications)
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent / "android"
manifest = root / "app" / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text()

m = re.sub(r'android:label="[^"]*"', 'android:label="Daily Report NKA"', m, count=1)

perms = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.READ_CONTACTS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.VIBRATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.REQUEST_INSTALL_PACKAGES",
]
perm_xml = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
m = re.sub(r"(<manifest[^>]*>\s*\n)", lambda x: x.group(1) + perm_xml, m, count=1)

receivers = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", receivers + "    </application>", 1)

# Update di dalam aplikasi (plugin ota_update): FileProvider untuk membuka APK unduhan
# di layar pasang Android, dan receiver hasil pemasangan.
ota = """
        <provider
            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
            android:authorities="${applicationId}.ota_update_provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/filepaths" />
        </provider>
        <receiver android:name="sk.fourq.otaupdate.InstallResultReceiver" android:exported="false">
            <intent-filter>
                <action android:name="${applicationId}.ACTION_INSTALL_COMPLETE"/>
            </intent-filter>
        </receiver>
"""
if "OtaUpdateFileProvider" not in m:
    m = m.replace("</application>", ota + "    </application>", 1)

xml_dir = root / "app" / "src" / "main" / "res" / "xml"
xml_dir.mkdir(parents=True, exist_ok=True)
(xml_dir / "filepaths.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<paths xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <files-path name="internal_apk_storage" path="ota_update/"/>\n'
    '</paths>\n'
)

queries = """
        <package android:name="com.whatsapp" />
        <package android:name="com.whatsapp.w4b" />
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="tel" />
        </intent>
"""
if "com.whatsapp.w4b" not in m:
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>" + queries, 1)
    else:
        m = m.replace("</manifest>", "    <queries>" + queries + "    </queries>\n</manifest>", 1)

manifest.write_text(m)
print("AndroidManifest.xml diperbarui")

KEYSTORE = str((root.parent / "ci" / "debug.keystore").resolve()).replace("\\", "/")
if not pathlib.Path(KEYSTORE).exists():
    sys.exit("ci/debug.keystore tidak ditemukan")

kts = root / "app" / "build.gradle.kts"
groovy = root / "app" / "build.gradle"
if kts.exists():
    g = kts.read_text()
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
    if "desugar_jdk_libs" not in g:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    # Tanda tangan APK selalu memakai ci/debug.keystore milik NKA (bukan kunci acak "Android Debug"
    # buatan Gradle), supaya APK baru bisa di-install di atas versi lama.
    if 'create("nka")' not in g:
        def add_kts(m):
            i = m.group(1)
            return (f'{i}signingConfigs {{{i}    create("nka") {{{i}        storeFile = file("{KEYSTORE}"){i}'
                    f'        storePassword = "android"{i}        keyAlias = "androiddebugkey"{i}'
                    f'        keyPassword = "android"{i}    }}{i}}}{i}buildTypes {{')
        g = re.sub(r"(\n[ \t]*)buildTypes\s*\{", add_kts, g, count=1)
        g = g.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("nka")')
    if 'getByName("nka")' not in g:
        sys.exit("Gagal memasang signing config NKA di build.gradle.kts")
    kts.write_text(g)
    print("build.gradle.kts diperbarui")
elif groovy.exists():
    g = groovy.read_text()
    if "coreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", g, count=1)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    if "signingConfigs.nka" not in g:
        def add_groovy(m):
            i = m.group(1)
            return (f"{i}signingConfigs {{{i}    nka {{{i}        storeFile file('{KEYSTORE}'){i}"
                    f"        storePassword 'android'{i}        keyAlias 'androiddebugkey'{i}"
                    f"        keyPassword 'android'{i}    }}{i}}}{i}buildTypes {{")
        g = re.sub(r"(\n[ \t]*)buildTypes\s*\{", add_groovy, g, count=1)
        g = g.replace("signingConfigs.debug", "signingConfigs.nka")
    if "signingConfigs.nka" not in g:
        sys.exit("Gagal memasang signing config NKA di build.gradle")
    groovy.write_text(g)
    print("build.gradle diperbarui")
else:
    sys.exit("build.gradle tidak ditemukan")
