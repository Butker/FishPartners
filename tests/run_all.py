#!/usr/bin/env python3
"""Run every scenario test against a mock WoW API.  pip install lupa  ->  python tests/run_all.py"""
import glob, os, re, sys, lupa
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
failed = []
for path in sorted(glob.glob(os.path.join(here, "run*.lua"))):
    L = lupa.LuaRuntime()
    L.globals().ADDON_ROOT = root
    L.globals().TESTS = here
    out = []
    L.globals().print = lambda *a: out.append("\t".join(str(x) for x in a))
    name = os.path.basename(path)
    try:
        L.execute('dofile(TESTS .. "/' + name + '")')
        text = "\n".join(out)
        bad = re.search(r"^FAIL|errors:\t[1-9]", text, re.M)
        ok = re.search(r"^OK", text, re.M) and not bad
    except Exception as e:
        ok, text = False, str(e)
    print(("PASS  " if ok else "FAIL  ") + name)
    if not ok: failed.append(name); print(text[-1500:])
print(f"\n{len(failed)} failed" if failed else "\nall passed")
sys.exit(1 if failed else 0)
