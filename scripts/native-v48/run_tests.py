#!/usr/bin/env python3
"""Run all offline V4.8 kit regression tests, without modifying Odysseus."""
import pathlib, subprocess, sys
root=pathlib.Path(__file__).resolve().parent
folders=sorted(p for p in root.iterdir() if p.is_dir())
for folder in folders:
    if not list(folder.glob('test_*.py')): continue
    print(f"\n### {folder.name}",flush=True)
    proc=subprocess.run([sys.executable,'-m','unittest','discover','-s',str(folder),'-p','test_*.py','-v'],timeout=90)
    if proc.returncode: raise SystemExit(f"Offline regression failure: {folder.name}")
print("All available offline patch-kit suites passed.")
