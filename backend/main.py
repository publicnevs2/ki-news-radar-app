# backend/main.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import json
from .database import get_db_connection
from datetime import datetime

app = FastAPI(title="KI-News-Radar API")

# CORS-Middleware, damit deine App vom Handy aus zugreifen kann
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Für die Entwicklung, später einschränken!
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/articles")
def get_all_articles():
    """Gibt alle Artikel aus der Datenbank zurück, sortiert nach Datum."""
    conn = get_db_connection()
    articles_raw = conn.execute("SELECT * FROM articles ORDER BY published DESC").fetchall()
    conn.close()
    
    # Konvertiere die DB-Zeilen in Dictionaries und parse den Topics-JSON-String
    articles = []
    for row in articles_raw:
        article = dict(row)
        article['topics'] = json.loads(article.get('topics', '[]'))
        articles.append(article)
        
    return articles

@app.get("/api/summary")
def get_daily_summary():
    """Gibt das neueste Tages-Briefing zurück."""
    conn = get_db_connection()
    summary_raw = conn.execute("SELECT summary_text FROM summaries ORDER BY date DESC LIMIT 1").fetchone()
    conn.close()
    
    if summary_raw is None:
        return {"summary_text": "Kein Tages-Briefing verfügbar."}
        
    return {"summary_text": summary_raw['summary_text']}