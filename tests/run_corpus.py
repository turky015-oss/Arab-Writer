#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
اختبار المجموعة الثابتة: نصوص لم تُصَغ من قاموس الفاحص، فتقيس الإنذارات الكاذبة وما يفلت.
يفشل إذا تغيّر عدد الأخطاء المانعة على أي نص عمّا في corpus/expect.json.
الاستعمال: python3 tests/run_corpus.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
import ar_lint  # noqa: E402

CORPUS = os.path.join(HERE, "corpus")
with open(os.path.join(CORPUS, "expect.json"), encoding="utf-8") as f:
    EXPECT = json.load(f)

ok = bad = 0


def blob(items):
    return " | ".join(f"{i['msg']} {i.get('at', '')}" for i in items)


for name, exp in EXPECT.items():
    if name.startswith("_"):
        continue
    with open(os.path.join(CORPUS, name), encoding="utf-8") as f:
        text = f.read()
    r, _ = ar_lint.check(text)
    problems = []
    if len(r.blocking) != exp["blocking"]:
        problems.append(f"الأخطاء المانعة {len(r.blocking)} والمقفل {exp['blocking']}: {blob(r.blocking)}")
    bl, wn = blob(r.blocking), blob(r.warnings)
    problems += [f"لم يُمنع: {m}" for m in exp.get("must_block", []) if m not in bl]
    problems += [f"لم يُنبَّه: {m}" for m in exp.get("must_warn", []) if m not in wn]
    problems += [f"مُنع بلا داعٍ: {m}" for m in exp.get("must_pass", []) if m in bl]
    if "strict_blocking" in exp:
        rs, _ = ar_lint.check(text, strict_style=True)
        if len(rs.blocking) != exp["strict_blocking"]:
            problems.append(f"مع --strict-style: {len(rs.blocking)} والمقفل {exp['strict_blocking']}")
    if problems:
        bad += 1
        print(f"✗ {name} ({exp['label']})")
        for p in problems:
            print("    " + p)
    else:
        ok += 1
        print(f"✓ {name} ({exp['label']}): {len(r.blocking)} مانع، {len(r.warnings)} تنبيه")

print(f"\nالنتيجة: {ok} ناجح، {bad} فاشل")
sys.exit(1 if bad else 0)
