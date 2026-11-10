#!/usr/bin/env python3
"""يلتقط صور شاشة من التطبيق على محاكي أندرويد: يفتح كل قسم بالضغط على اسمه."""
import os, re, subprocess, sys, time
import xml.etree.ElementTree as ET

PKG = "app.arabwriter.android"
OUT = sys.argv[1] if len(sys.argv) > 1 else "shots"
os.makedirs(OUT, exist_ok=True)

def sh(*a, check=False):
    return subprocess.run(["adb", "shell", *a], capture_output=True, text=True, check=check).stdout

def shot(name):
    time.sleep(2.5)
    with open(f"{OUT}/{name}.png", "wb") as f:
        f.write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout)
    print("✓", name)

def nodes():
    sh("uiautomator", "dump", "/sdcard/ui.xml")
    xml = subprocess.run(["adb", "exec-out", "cat", "/sdcard/ui.xml"], capture_output=True).stdout.decode("utf-8", "ignore")
    try:
        return list(ET.fromstring(xml).iter("node"))
    except ET.ParseError:
        return []

def opened():
    return any(n.get("content-desc", "") == "رجوع" for n in nodes())

def tap_text(text, tries=4, verify=True):
    for _ in range(tries):
        for n in nodes():
            if n.get("text", "").strip() == text or n.get("content-desc", "").strip() == text:
                x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get("bounds")))
                for _ in range(3):
                    sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
                    for _ in range(6):
                        time.sleep(1)
                        if not verify or opened():
                            return True
                print("… إعادة الضغط", text)
                return False
        sh("input", "swipe", "540", "1700", "540", "900", "300")  # لو العنصر تحت
        time.sleep(1)
    print("✗ ما لقيت", text)
    return False

def back():
    sh("input", "keyevent", "4"); time.sleep(1.5)

def launch():
    sh("am", "force-stop", PKG)
    sh("monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(5)

launch()
shot("01-home")
sections = [("الكتابة", "02-writer"), ("الفاحص", "03-checker"), ("الترجمة", "04-translate"),
            ("القصة", "05-story"), ("الفيديو", "06-video"), ("وورد", "07-word"),
            ("إكسل", "08-sheet"), ("PDF", "09-pdf")]
for title, name in sections:
    launch()
    if tap_text(title):
        shot(name)

launch()
if tap_text("داخلي · بدون إنترنت") or tap_text("الأدوات فقط") or tap_text("Claude متصل"):
    shot("10-settings")

# نص عربي يوصل من «مشاركة» ويفتح قسم الكتابة
sample = "الذكاء الاصطناعي يلعب دوراً محورياً في تطوير الأعمال، والنتيجه كانت ممتازه امس."
sh("am", "force-stop", PKG)
r = subprocess.run(["adb", "shell", f"am start -W --activity-clear-task -a android.intent.action.SEND -t text/plain -n {PKG}/.ui.MainActivity --es android.intent.extra.TEXT '{sample}'"], capture_output=True, text=True)
print(r.stdout, r.stderr)
for _ in range(10):
    time.sleep(1)
    if opened(): break
shot("11-writer-text")

sh("cmd", "uimode", "night", "yes")
launch()
shot("12-home-dark")
if tap_text("الترجمة"):
    shot("13-translate-dark")
sh("cmd", "uimode", "night", "no")
