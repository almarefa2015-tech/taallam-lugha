"""Generate word images with the Gemini API (free tier only, hard cap on count)."""
import base64, json, os, sys, time, urllib.request, urllib.error

KEY = os.environ.get("GEMINI_API_KEY", "")
BASE = "https://generativelanguage.googleapis.com/v1beta"
MAX_IMAGES = 5  # hard safety cap for the test run
OUT_DIR = "assets/words"
LOG = []

def log(msg):
    print(msg); LOG.append(msg)

def call(url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", "x-goog-api-key": KEY})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {"error": str(e)}

def image_models():
    st, res = call(f"{BASE}/models?pageSize=200")
    if st != 200:
        log(f"list models failed {st}: {json.dumps(res)[:500]}"); return []
    names = []
    for m in res.get("models", []):
        n = m["name"]
        if "image" in n and "generateContent" in m.get("supportedGenerationMethods", []):
            names.append(n)
    log("image models: " + ", ".join(names))
    # prefer lite, then flash
    names.sort(key=lambda n: (0 if "lite" in n else 1 if "flash" in n else 2, n))
    return names

def generate(model, prompt):
    body = {"contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]}}
    st, res = call(f"{BASE}/{model}:generateContent", body)
    if st != 200:
        return None, f"{st}: {json.dumps(res)[:400]}"
    for c in res.get("candidates", []):
        for p in c.get("content", {}).get("parts", []):
            d = p.get("inlineData") or p.get("inline_data")
            if d and d.get("data"):
                return base64.b64decode(d["data"]), None
    return None, "no image in response: " + json.dumps(res)[:400]

def main():
    if not KEY:
        log("GEMINI_API_KEY missing"); return
    items = json.load(open(sys.argv[1]))[:MAX_IMAGES]
    models = image_models()
    os.makedirs(OUT_DIR, exist_ok=True)
    for it in items:
        path = os.path.join(OUT_DIR, it["file"])
        if os.path.exists(path):
            log(f"skip {it['file']} (exists)"); continue
        done = False
        for m in models:
            img, err = generate(m, it["prompt"])
            if img:
                open(path, "wb").write(img); log(f"OK {it['file']} via {m}"); done = True; break
            log(f"FAIL {it['file']} via {m}: {err}")
            if err and err.startswith("429"):
                time.sleep(20)
        if not done:
            log(f"GAVE UP {it['file']}")
        time.sleep(8)

if __name__ == "__main__":
    try:
        main()
    finally:
        os.makedirs("tools/logs", exist_ok=True)
        open("tools/logs/last_run.txt", "w").write("\n".join(LOG) + "\n")
