import json
from pathlib import Path

from graphify.detect import detect
from graphify.paths import out_path
from graphify.watch import _read_build_excludes, _read_build_gitignore

result = detect(
    Path("."),
    extra_excludes=_read_build_excludes(out_path()),
    gitignore=_read_build_gitignore(out_path()),
)
Path("graphify-out/.graphify_detect.json").write_text(
    json.dumps(result, ensure_ascii=False), encoding="utf-8"
)

counts = {k: len(v) for k, v in result.get("files", {}).items()}
print("total_files:", result.get("total_files"))
print("total_words:", result.get("total_words"))
print("skipped_sensitive:", result.get("skipped_sensitive"))
print("scan_root:", result.get("scan_root"))
print("counts:", json.dumps(counts))
for cat, files in result.get("files", {}).items():
    if files:
        print(f"--- {cat} ({len(files)}) ---")
        for f in files[:40]:
            print("  ", f)
