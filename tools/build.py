"""Вставляет plan/plan.json в index.html (между /*PLAN*/ и /*/PLAN*/).

python3 tools/build.py                                   — обновить index.html
python3 tools/build.py --ref IMG --photos DIR --out OUT  — ещё собрать закрытое превью OUT:
    с подложкой 2ГИС (IMG) и фото точек съёмки (DIR/IMG_xxxx.jpg). Скриншоты и фото
    в публичный репозиторий не кладём.
"""
import argparse, base64, json, pathlib, re

root = pathlib.Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser()
ap.add_argument("--ref"); ap.add_argument("--photos"); ap.add_argument("--out")
a = ap.parse_args()

plan = json.loads((root / "plan" / "plan.json").read_text(encoding="utf-8"))
html_path = root / "index.html"
html = html_path.read_text(encoding="utf-8")
blob = json.dumps(plan, ensure_ascii=False, separators=(",", ":"))
html, n = re.subn(r"/\*PLAN\*/.*?/\*/PLAN\*/", lambda m: f"/*PLAN*/const PLAN={blob};/*/PLAN*/", html, flags=re.S)
assert n == 1, "метка /*PLAN*/ не найдена"
html_path.write_text(html, encoding="utf-8")
print("index.html: план вставлен")

if a.out:
    b64 = lambda p: "data:image/jpeg;base64," + base64.b64encode(pathlib.Path(p).read_bytes()).decode()
    extra = ""
    if a.ref:
        extra += f"window.REF_2GIS='{b64(a.ref)}';\n"
    if a.photos:
        ph = {v["photo"]: b64(pathlib.Path(a.photos) / (v["photo"] + ".jpg")) for v in plan["viewpoints"]}
        extra += "window.REF_PHOTOS=" + json.dumps(ph) + ";\n"
    tag = '<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>'
    out = html.replace(tag, "<script>\n" + extra + "</script>\n" + tag, 1)
    pathlib.Path(a.out).write_text(out, encoding="utf-8")
    print("закрытое превью:", a.out)
