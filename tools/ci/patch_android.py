"""Patch the generated Android project: permissions, speech/TTS queries, app label."""
import re, pathlib
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = m.read_text()
perms = ('<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n'
         '    <uses-permission android:name="android.permission.INTERNET"/>\n'
         '    <uses-permission android:name="android.permission.BLUETOOTH"/>\n'
         '    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>\n'
         '    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>\n')
if 'RECORD_AUDIO' not in s:
    s = re.sub(r'(<manifest[^>]*>)', r'\1\n    ' + perms.replace('\\', '\\\\'), s, count=1)
q = ('<intent><action android:name="android.speech.RecognitionService"/></intent>\n'
     '        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>\n'
     '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n')
if '<queries>' in s:
    s = s.replace('<queries>', '<queries>\n        ' + q, 1)
else:
    s = s.replace('</manifest>', '    <queries>\n        ' + q + '    </queries>\n</manifest>')
s = re.sub(r'android:label="[^"]*"', 'android:label="تعلم لغة"', s, count=1)
m.write_text(s)
print(s)
