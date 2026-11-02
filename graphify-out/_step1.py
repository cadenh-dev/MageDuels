import os, sys
from pathlib import Path

Path("graphify-out").mkdir(parents=True, exist_ok=True)
Path("graphify-out/.graphify_python").write_text(sys.executable, encoding="utf-8")
root = os.path.abspath(".")
Path("graphify-out/.graphify_root").write_text(root, encoding="utf-8")
print("python:", sys.executable)
print("root:", root)
