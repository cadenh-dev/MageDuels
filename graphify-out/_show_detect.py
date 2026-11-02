import json
from pathlib import Path

d = json.loads(Path("graphify-out/.graphify_detect.json").read_text(encoding="utf-8"))
counts = {k: len(v) for k, v in d.get("files", {}).items()}
print("total_files:", d.get("total_files"), "words:", d.get("total_words"), "counts:", counts)
for cat, files in d.get("files", {}).items():
    for f in files:
        print(f"{cat}\t{f}")
