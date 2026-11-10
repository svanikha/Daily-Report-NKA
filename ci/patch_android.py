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

kts = root / "app" / "build.gradle.kts"
groovy = root / "app" / "build.gradle"
if kts.exists():
    g = kts.read_text()
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
    if "desugar_jdk_libs" not in g:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(g)
    print("build.gradle.kts diperbarui")
elif groovy.exists():
    g = groovy.read_text()
    if "coreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", g, count=1)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(g)
    print("build.gradle diperbarui")
else:
    sys.exit("build.gradle tidak ditemukan")
