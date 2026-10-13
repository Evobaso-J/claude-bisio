"""Build the candidate review page (HOF-styled, db-backed approve + rename).

Usage: python3 -I build_review.py <candidates.json> <first_dex> <out.html>
candidates.json: [{"id": "c1", "name": "pomodorisio", "note": "...", "warn": false, "png": "/abs/path.png"}, ...]
Each png is a normalised cutout; it is downscaled to 320px and inlined.
"""
import base64, json, pathlib, subprocess, sys, tempfile

cands = json.loads(pathlib.Path(sys.argv[1]).read_text())
tpl = (pathlib.Path(__file__).parent / "review.tpl.html").read_text()
items = []
with tempfile.TemporaryDirectory() as tmp:
    for c in cands:
        thumb = pathlib.Path(tmp) / f"{c['id']}.png"
        subprocess.run(["magick", c["png"], "-resize", "320x320", "-strip", f"PNG32:{thumb}"], check=True)
        src = "data:image/png;base64," + base64.b64encode(thumb.read_bytes()).decode()
        items.append({"id": c["id"], "name": c["name"], "note": c["note"], "warn": c.get("warn", False), "src": src})
html = tpl.replace("__DATA__", json.dumps(items)).replace("__FIRST_DEX__", str(int(sys.argv[2])))
pathlib.Path(sys.argv[3]).write_text(html)
print(f"wrote {sys.argv[3]} ({len(items)} candidates)")
