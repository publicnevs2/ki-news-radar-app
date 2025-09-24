import requests, json
from urllib.parse import urljoin

BASE_URL = "http://192.168.178.21:8191/"
API_TOKEN = "0e62ff9b58e8bb5754758020d9a78e86298a5d45"  # ← hier einsetzen

s = requests.Session()
s.headers.update({"Authorization": f"Token {API_TOKEN}"})

next_url = "api/documents/?ordering=-created&query=e&page=1"

with open("paperless_full_export.ndjson","w",encoding="utf-8") as out, \
     open("all_texts.txt","w",encoding="utf-8") as texts:
    while next_url:
        r = s.get(urljoin(BASE_URL, next_url), timeout=60)
        r.raise_for_status()
        data = r.json()
        for doc in data["results"]:
            # Ganze JSON-Zeile (inkl. OCR-Text) in NDJSON
            out.write(json.dumps(doc, ensure_ascii=False) + "\n")
            # Nur reiner Text für Suchzwecke
            texts.write(f"\n\n===== DOCUMENT #{doc['id']} | {doc.get('title','')} =====\n")
            texts.write(doc.get("content",""))
        next_url = data.get("next")

print("Fertig: paperless_full_export.ndjson + all_texts.txt")
