# backend/database.py
import sqlite3
import os

DB_FILE = "news_radar.db"

def get_db_connection():
    """Stellt eine Verbindung zur SQLite-Datenbank her."""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row # Ermöglicht den Zugriff auf Spalten über ihren Namen
    return conn

def init_db():
    """Initialisiert die Datenbank und erstellt die Tabellen, falls sie nicht existieren."""
    if os.path.exists(DB_FILE):
        print("Datenbank existiert bereits.")
        return

    print("Erstelle neue Datenbank...")
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Tabelle für die Artikel
    cursor.execute('''
        CREATE TABLE articles (
            link TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            title TEXT NOT NULL,
            published TEXT NOT NULL,
            summary_ai TEXT,
            type TEXT,
            audio_url TEXT,
            topics TEXT
        )
    ''')
    
    # Tabelle für die täglichen Zusammenfassungen
    cursor.execute('''
        CREATE TABLE summaries (
            date TEXT PRIMARY KEY,
            summary_text TEXT NOT NULL
        )
    ''')
    
    conn.commit()
    conn.close()
    print("Datenbank erfolgreich initialisiert.")

if __name__ == '__main__':
    init_db()