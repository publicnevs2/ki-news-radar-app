# backend/tasks.py (Final Version)

import os
import json
import feedparser
from datetime import datetime, timezone
import re
import time
import random
import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv

# --- Local Imports ---
from .database import get_db_connection

# --- GOOGLE GEN AI SDK ---
from google import genai
from google.genai import types

# --- CONFIGURATION ---
load_dotenv()

client = genai.Client(
    api_key=os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
)

# Stabile Modell-IDs
MODEL_JSON = "gemini-1.5-flash-latest" 
MODEL_SUMMARY = "gemini-1.5-pro-latest"

MAX_ENTRIES_PER_RUN = 40
ARTICLES_TO_SCRAPE_FOR_BRIEFING = 5
BATCH_SIZE = 10
MAX_RETRIES = 3

RSS_FEEDS = {
    "Heise KI Update": {"url": "https://kiupdate.podigee.io/feed/mp3", "type": "podcast"},
    "AI First": {"url": "https://feeds.captivate.fm/ai-first/", "type": "podcast"},
    "KI Inside": {"url": "https://agidomedia.podcaster.de/insideki.rss", "type": "podcast"},
    "Your CoPilot": {"url": "https://podcast.yourcopilot.de/feed/mp3", "type": "podcast"},
    "Heise (Thema KI)": {"url": "https://www.heise.de/thema/kuenstliche-intelligenz/rss.xml", "type": "article"},
    "t3n (Thema KI)": {"url": "https://t3n.de/tag/ki/rss", "type": "article"},
}

PROMPT_ITEM = """- id: "{id}"
  title: "{title}"
  content: "{content}"
"""

PROMPT_BATCH = """Du bekommst eine Liste von Artikeln/Podcast-Beschreibungen. Fasse **für jedes Element** separat zusammen.
Aufgabe je Element:
- Erstelle eine **prägnante deutsche Zusammenfassung** in max. drei Sätzen.
- Extrahiere **bis zu drei** relevante **Themen** als Stichwörter.
WICHTIG: Antworte **ausschließlich** mit einem **validen JSON-Array**.
Erwartetes Format:
[
  {{"id":"<id>","summary":"<deutsche Zusammenfassung>","topics":["<topic1>","<topic2>"]}},
  ...
]
Hier sind die Items:
---
{items}
---
"""

SUMMARY_PROMPT = """Du bist ein erfahrener Tech-Journalist für ein deutsches Publikum. Analysiere die folgenden VOLLSTÄNDIGEN Artikeltexte des heutigen Tages.
Deine Aufgabe ist es, ein professionelles, flüssig lesbares KI-News-Briefing für heute zu schreiben.
Beginne mit einer prägnanten, fesselnden Schlagzeile. Fasse die wichtigsten Erkenntnisse zusammen und zeige Verbindungen zwischen den Nachrichten auf.
Strukturiere den Text in sinnvolle Absätze. Nenne KEINE Quellen im Text. Gib nur den fertigen Briefing-Text zurück.
Artikeltexte:
---
{}
---"""

# --- Helper & Core Functions ---

def scrape_article_text(url):
    try:
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'}
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "lxml")
        main_content = soup.find("article") or soup.find("main") or soup.find("div", class_=re.compile(r"content|post|body|article"))
        if not main_content: return None
        for element in main_content(["script", "style", "nav", "footer", "header", "aside"]):
            element.decompose()
        text = main_content.get_text(separator="\n", strip=True)
        return text if len(text) > 200 else None
    except Exception as e:
        print(f"-> Fehler beim Scrapen von {url}: {e}")
        return None

def get_processed_links_from_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT link FROM articles")
    links = {row["link"] for row in cursor.fetchall()}
    conn.close()
    return links

def save_articles_to_db(articles):
    if not articles: return 0
    conn = get_db_connection()
    cursor = conn.cursor()
    for article in articles:
        topics_str = json.dumps(article.get("topics", []))
        cursor.execute("INSERT OR IGNORE INTO articles (link, source, title, published, summary_ai, type, audio_url, topics) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                       (article["link"], article["source"], article["title"], article["published"], article["summary_ai"], article["type"], article["audio_url"], topics_str))
    count = conn.total_changes
    conn.commit()
    conn.close()
    return count

def save_summary_to_db(summary_text):
    today_str = datetime.now().strftime("%Y-%m-%d")
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("INSERT OR REPLACE INTO summaries (date, summary_text) VALUES (?, ?)", (today_str, summary_text))
    conn.commit()
    conn.close()

def get_new_entries(processed_links):
    all_new_entries = []
    print("Starte das Abrufen der Feeds auf neue Einträge...")
    for name, feed_info in RSS_FEEDS.items():
        try:
            feed = feedparser.parse(feed_info["url"])
            for entry in feed.entries:
                link = getattr(entry, "link", None)
                if not link or link in processed_links: continue
                published_time = entry.get("published_parsed")
                dt_object = datetime.now(timezone.utc)
                if published_time:
                    dt_object = datetime(*published_time[:6], tzinfo=timezone.utc)
                content = entry.get("summary", "")
                clean_content = re.sub("<[^<]+?>", "", content or "")
                audio_url = ""
                if feed_info["type"] == "podcast":
                    for enc in getattr(entry, "enclosures", []):
                        if "audio" in getattr(enc, "type", ""):
                            audio_url = getattr(enc, "href", "")
                            break
                all_new_entries.append({
                    "source": name, "title": getattr(entry, "title", "Ohne Titel"), "link": link,
                    "published": dt_object.isoformat(), "type": feed_info["type"],
                    "content_raw": (clean_content or "")[:2000], "audio_url": audio_url,
                })
        except Exception as e:
            print(f"Fehler beim Abrufen von Feed {name}: {e}")
    all_new_entries.sort(key=lambda x: x["published"], reverse=True)
    limited_entries = all_new_entries[:MAX_ENTRIES_PER_RUN]
    print(f"{len(all_new_entries)} neue Einträge gefunden. Verarbeite die {len(limited_entries)} neuesten.")
    return limited_entries

def process_with_gemini(entries):
    if not entries: return []
    print(f"\nStarte die Verarbeitung von {len(entries)} neuen Einträgen mit Gemini (Batchgröße {BATCH_SIZE})...")
    
    enriched = [dict(e, id=f"item_{i}") for i, e in enumerate(entries)]
    processed_by_id = {}

    for batch in [enriched[i:i + BATCH_SIZE] for i in range(0, len(enriched), BATCH_SIZE)]:
        items_text = "".join([PROMPT_ITEM.format(id=e["id"], title=(e["title"] or "").replace('"', ''), content=(e["content_raw"] or "").replace('"', '').replace("\n", " ")) for e in batch])
        prompt = PROMPT_BATCH.format(items=items_text)
        
        for attempt in range(MAX_RETRIES):
            try:
                response = client.generate_content(model=f"models/{MODEL_JSON}", contents=prompt)
                raw_text = response.text
                
                json_match = re.search(r"\[.*\]", raw_text, re.DOTALL)
                if not json_match: raise ValueError("Kein JSON-Array im Modell-Output gefunden")
                
                data = json.loads(json_match.group(0))
                for obj in data:
                    if _id := obj.get("id"):
                        processed_by_id[_id] = {"summary": obj.get("summary", ""), "topics": obj.get("topics", [])}
                print(f"-> Batch mit {len(batch)} Items verarbeitet.")
                break
            except Exception as e:
                delay = (2 ** attempt) + random.uniform(0, 1)
                print(f"-> Fehler im Batch, Retry {attempt+1}/{MAX_RETRIES} in {delay:.1f}s: {e}")
                if attempt + 1 < MAX_RETRIES: time.sleep(delay)
                else: print(f"-> FEHLER (final) im Batch nach {MAX_RETRIES} Versuchen.")

    processed_entries = []
    for e in enriched:
        if info := processed_by_id.get(e["id"]):
            e.update({"summary_ai": info["summary"], "topics": info["topics"]})
            e.pop("content_raw", None); e.pop("id", None)
            processed_entries.append(e)

    print(f"Gesamt verarbeitet: {len(processed_entries)} / {len(entries)}")
    return processed_entries

def generate_and_save_daily_summary(newly_processed_articles):
    print("\nStarte die Erstellung des Tages-Briefings...")
    if not newly_processed_articles: return

    articles_to_process = [a for a in newly_processed_articles if a["type"] == "article"][:ARTICLES_TO_SCRAPE_FOR_BRIEFING]
    content_for_summary = ""
    
    if articles_to_process:
        print(f"Scrape die {len(articles_to_process)} wichtigsten Artikel für mehr Kontext...")
        scraped_texts = [scrape_article_text(a["link"]) for a in articles_to_process]
        scraped_content = [f"ARTIKELTITEL: {a['title']}\nVOLLTEXT: {text[:8000]}\n---" for a, text in zip(articles_to_process, scraped_texts) if text]
        if scraped_content:
            content_for_summary = "\n\n".join(scraped_content)
            print("Sende Volltexte für die finale Synthese...")
        else:
            print("Konnte keine Artikelinhalte herunterladen. Weiche auf Fallback aus.")

    if not content_for_summary:
        print("Erstelle einfaches Briefing aus den vorhandenen Zusammenfassungen...")
        content_for_summary = "\n\n".join([f"Titel: {a['title']}\nZusammenfassung: {a['summary_ai']}" for a in newly_processed_articles])
    
    try:
        response = client.generate_content(model=f"models/{MODEL_SUMMARY}", contents=SUMMARY_PROMPT.format(content_for_summary))
        save_summary_to_db(response.text.strip())
        print("✅ Tages-Briefing erfolgreich erstellt und in der DB gespeichert.")
    except Exception as e:
        print(f"-> FEHLER bei der Erstellung der Tageszusammenfassung: {e}")

def run_daily_task():
    processed_links = get_processed_links_from_db()
    new_entries = get_new_entries(processed_links)
    if new_entries:
        successfully_processed = process_with_gemini(new_entries)
        if successfully_processed:
            saved_count = save_articles_to_db(successfully_processed)
            print(f"\n✅ {saved_count} neue Einträge zur Datenbank hinzugefügt.")
            generate_and_save_daily_summary(successfully_processed)
        else:
            print("\nKeine neuen Einträge konnten erfolgreich verarbeitet werden.")
    else:
        print("\nKeine neuen Einträge in den Feeds gefunden.")

if __name__ == "__main__":
    run_daily_task()