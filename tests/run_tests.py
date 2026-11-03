#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
اختبارات Arab Writer: يشغّل الفاحص على حالات معروفة ويتحقق أن:
1. كل خطأ مزروع يُكتشف.
2. النصوص النظيفة تمر بلا خطأ مانع (لا إنذارات كاذبة).
3. الإصلاح الآلي يصحح ما يجب ولا يكسر النص.

الاستعمال: python3 tests/run_tests.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
import ar_lint  # noqa: E402

with open(os.path.join(HERE, "cases.json"), encoding="utf-8") as f:
    CASES = json.load(f)

passed = failed = 0


def blob(report):
    return " | ".join(f"{i['kind']} {i['msg']}" for i in report.items)


for c in CASES["detect"]:
    r, _ = ar_lint.check(c["text"], words_target=c.get("words"), source=c.get("source"))
    b = blob(r)
    missing = [m for m in c["must_find"] if m not in b]
    if missing:
        failed += 1
        print(f"✗ كشف: {c['name']} — لم يُكتشف: {missing}")
    else:
        passed += 1
        print(f"✓ كشف: {c['name']}")

for c in CASES["clean"]:
    r, _ = ar_lint.check(c["text"], en_lines=c.get("en_lines", True))
    if r.blocking:
        failed += 1
        print(f"✗ نظيف: {c['name']} — إنذار كاذب: {blob(r)}")
    else:
        passed += 1
        print(f"✓ نظيف: {c['name']}")

for c in CASES["fix"]:
    out = ar_lint.fix(c["text"])
    bad = [w for w in c.get("must_contain", []) if w not in out] + \
          [w for w in c.get("must_not_contain", []) if w in out]
    if bad:
        failed += 1
        print(f"✗ إصلاح: {c['name']} — {bad}\n    الناتج: {out!r}")
    else:
        passed += 1
        print(f"✓ إصلاح: {c['name']}")

print(f"\nالنتيجة: {passed} ناجح، {failed} فاشل")
sys.exit(1 if failed else 0)
