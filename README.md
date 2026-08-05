# 🏀 Pickup – Basketball Team Builder

Pickup ist eine mobile Web-App für eure Basketballgruppe. Teams werden fair und schnell zusammengestellt, Ergebnisse gespeichert und Statistiken automatisch ausgewertet.

---

## App auf dem Smartphone installieren

### Android (Chrome)
1. Die App-URL im Chrome-Browser öffnen
2. Oben rechts auf die **drei Punkte** tippen
3. **„App installieren"** oder **„Zum Startbildschirm hinzufügen"** wählen
4. Namen bestätigen → **„Installieren"**

Das Basketball-Icon erscheint sofort auf dem Homescreen und die App startet wie eine native App – ohne Browser-Leiste.

### iPhone (Safari)
1. Die App-URL in **Safari** öffnen (nicht Chrome)
2. Unten in der Mitte das **Teilen-Icon** antippen (Quadrat mit Pfeil nach oben)
3. Im Menü nach unten scrollen → **„Zum Home-Bildschirm"** antippen
4. Name auf **„Pickup"** lassen → **„Hinzufügen"**

---

## Funktionen der App

### 👥 Tab: Spieler

Hier werden alle Spieler verwaltet. Die Daten sind für alle Mitspieler sichtbar und werden in Echtzeit synchronisiert.

**Spieler anlegen**
1. Auf den orangenen **＋ Button** unten rechts tippen
2. Spitzname eingeben – erscheint groß und zuerst auf der Karte
3. Vollständigen Namen eingeben (Pflichtfeld)
4. Optional: Handynummer und E-Mail für Einladungen
5. **Position** auswählen: PG · SG · SF · PF · C
6. **Rating** in 5 Kategorien vergeben (je 1–5 Sterne):
   - **Offense** – Angriffsstärke
   - **Defense** – Verteidigungsstärke
   - **Rebound** – Rebound-Stärke
   - **Einsatz** – Einsatzbereitschaft
   - **Kondition** – Ausdauer
7. Der **Tier** wird automatisch berechnet und als Vorschau angezeigt
8. Auf **„Speichern"** tippen

**Tier-System** (basiert auf dem Durchschnitt aller 5 Kategorien)
| Tier | Durchschnitt | Symbol |
|------|-------------|--------|
| Bronze | unter 2.0 | 🥉 |
| Silber | 2.0 – 3.2 | 🥈 |
| Gold | 3.2 – 4.2 | 🥇 |
| Elite | ab 4.2 | 💎 |

**Spieler aktivieren / deaktivieren**
- Auf den Spieler tippen → wechselt zwischen aktiv (grüner Punkt) und abwesend
- Abwesende Spieler erscheinen automatisch im Bereich **„Bank – Abwesend heute"**

**Neuer Spieltag**
- Oben auf **„🏀 Neuer Spieltag – alle aktivieren"** tippen
- Alle Spieler werden auf einmal auf aktiv gesetzt

**Rating ein-/ausblenden**
- Unter jedem Spieler auf **„Rating anzeigen / ausblenden"** tippen
- Die 5 Kategorien mit Balkenanzeige klappen auf bzw. zu

**Spieler einladen**
- Bei Spielern mit hinterlegter Nummer oder E-Mail erscheint ein **📲 Icon**
- Antippen öffnet das native Share-Menü mit WhatsApp, SMS und weiteren Optionen

**Spieler bearbeiten oder löschen**
- ✏️ öffnet das Bearbeitungsformular
- 🗑️ löscht den Spieler nach einer Bestätigung

---

### ⚙️ Tab: Teams bilden

Hier werden die Teams für den Spieltag konfiguriert.

**Spielmodus wählen**
- **2v2** – 2 Spieler pro Team
- **3v3** – 3 Spieler pro Team
- **4v4** – 4 Spieler pro Team

**Anzahl Teams**
- Mit **−** und **+** zwischen 2 und 4 Teams wählen
- Die App zeigt automatisch einen **Vorschlag** (blauer Pill) basierend auf der Anzahl aktiver Spieler – antippen um zu übernehmen

**Zuteilung**
- **🎲 Zufall** – Spieler werden zufällig verteilt
- **⚖️ Ausgeglichen** – Teams werden nach Stärke balanciert

**Balance-Methode** (nur bei „Ausgeglichen")
- **∑ Skill-Summe** – jeder Spieler kommt ins Team mit der niedrigsten Gesamtstärke
- **🐍 Snake-Draft** – abwechselnd von stark nach schwach zugeteilt

**Bankspieler**
- Wenn mehr Spieler aktiv sind als die Teams fassen, werden überzählige Spieler automatisch als Bankspieler zugeteilt
- Die App zeigt eine Warnung mit Anzahl und Namen der Bankspieler

---

### 🏆 Tab: Ergebnis

Zeigt die generierten Teams nach der Teamerstellung.

**Teams ansehen**
- Jedes Team in seiner Farbe (grün, orange, blau, lila)
- Tier-Icon, Position und Ø-Stärke pro Team sichtbar
- Bankspieler erscheinen als gestrichelte Karte

**Neu würfeln**
- **„🔀 Neu würfeln"** generiert neue Teams mit denselben Einstellungen

**Ergebnis erfassen**
1. Nach dem Spiel auf **„📝 Ergebnis erfassen"** tippen
2. Das gewinnende Team antippen – es wird grün hervorgehoben
3. Optional: Punkte eintragen
4. Oder **„🤝 Unentschieden"** wählen
5. Auf **„💾 Speichern"** tippen

Das Ergebnis wird dauerhaft in der Datenbank gespeichert und erscheint in der Statistik.

---

### 📊 Tab: Statistik

Ausgewertet werden alle gespeicherten Spielergebnisse.

**🏆 Siegquoten**
- Alle Spieler sortiert nach Gewinnquote
- Zeigt Siege (S), Niederlagen (N), Unentschieden (U) und Gesamtspiele

**🤝 Beste Duos**
- Spielerpaare, die zusammen am häufigsten gewonnen haben
- Mindestens 2 gemeinsame Spiele erforderlich

**📋 Letzte Spiele**
- Chronologische Liste der letzten 15 Spiele
- Mit Datum, Modus und Ergebnis je Team

---

## Hinweise

- **Alle Daten sind für alle Mitspieler sichtbar** – jeder kann Spieler anlegen und Ergebnisse eintragen
- **Echtzeit-Sync** – Änderungen anderer Spieler erscheinen automatisch ohne Neuladen
- **Offline** – die App bleibt nach der Installation auch ohne Netz aufrufbar; Änderungen werden jedoch erst bei Verbindung gespeichert
- **Adblock** – falls auf dem PC „Verbindungsfehler" erscheint, Adblock für `supabase.co` deaktivieren; auf dem Handy tritt dieses Problem nicht auf
