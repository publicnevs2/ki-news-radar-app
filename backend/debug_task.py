import os
import sys

print("--- START DIAGNOSE-SKRIPT ---")

try:
    print(f"Python-Version: {sys.version}")
    print(f"Aktueller Pfad: {os.getcwd()}")
    print("\n--- Überprüfe 'google' Import ---")

    # Wir importieren das 'google' Modul und schauen, woher es kommt
    import google
    print(f"SUCCESS: 'google' Modul importiert.")
    print(f"Pfad der 'google' Bibliothek: {google.__path__}")

    # Jetzt versuchen wir, 'genai' zu importieren
    from google import genai
    print(f"\nSUCCESS: 'genai' aus 'google' importiert.")
    
    # Überprüfen der Version, falls vorhanden
    if hasattr(genai, '__version__'):
        print(f"Version der 'google-genai' Bibliothek: {genai.__version__}")
    else:
        print("WARNUNG: Konnte keine Versionsnummer für 'genai' finden.")

    # Wir erstellen den Client
    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
    print(f"\nSUCCESS: genai.Client-Objekt erstellt.")

    # Jetzt lassen wir uns alle verfügbaren Methoden und Attribute des Objekts anzeigen
    print("\n--- Attribute des 'client' Objekts: ---")
    attributes = dir(client)
    for attr in attributes:
        print(attr)
    
    print("\n--- Überprüfung auf 'generate_content': ---")
    if 'generate_content' in attributes:
        print("✅ ERGEBNIS: 'generate_content' ist im Client-Objekt vorhanden!")
    else:
        print("❌ ERGEBNIS: 'generate_content' FEHLT im Client-Objekt!")

except Exception as e:
    print(f"\n--- FEHLER WÄHREND DER DIAGNOSE ---")
    print(f"Ein Fehler ist aufgetreten: {e}")
    import traceback
    traceback.print_exc()

finally:
    print("\n--- ENDE DIAGNOSE-SKRIPT ---")
