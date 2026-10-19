"""Build the candidate review page (HOF-styled, db-backed approve + rename).

Usage: python3 -I build_review.py <candidates.json> <first_dex> <out.html>
candidates.json: [{"id": "c1", "name": "pomodorisio", "note": "...", "warn": false, "png": "/abs/path.png"}, ...]
Each png is a normalised cutout; it is downscaled to 320px and inlined, next to
its chafa render with the banner preset (bin/preview-bisio.sh --chafa).
"""
import base64, json, pathlib, subprocess, sys, tempfile

cands = json.loads(pathlib.Path(sys.argv[1]).read_text())
here = pathlib.Path(__file__).resolve().parent
tpl = (here / "review.tpl.html").read_text()
preview = here.parents[3] / "bin" / "preview-bisio.sh"
items = []
with tempfile.TemporaryDirectory() as tmp:
    for c in cands:
        thumb = pathlib.Path(tmp) / f"{c['id']}.png"
        subprocess.run(["magick", c["png"], "-resize", "320x320", "-strip", f"PNG32:{thumb}"], check=True)
        term = pathlib.Path(tmp) / f"{c['id']}-term.png"
        subprocess.run(["sh", str(preview), "--chafa", str(term), c["png"]], check=True, stdout=subprocess.DEVNULL)
        uri = lambda p: "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()
        items.append({"id": c["id"], "name": c["name"], "note": c["note"], "warn": c.get("warn", False),
                      "src": uri(thumb), "term": uri(term)})
html = tpl.replace("__DATA__", json.dumps(items)).replace("__FIRST_DEX__", str(int(sys.argv[2])))
pathlib.Path(sys.argv[3]).write_text(html)
print(f"wrote {sys.argv[3]} ({len(items)} candidates)")
