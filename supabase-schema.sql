-- ============================================================
-- Basketball Team Builder – Supabase Schema
-- Im Supabase SQL Editor ausführen (Dashboard → SQL Editor → New Query)
-- ============================================================

-- Spieler
CREATE TABLE IF NOT EXISTS players (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  nickname    TEXT,
  position    TEXT NOT NULL CHECK (position IN ('PG','SG','SF','PF','C')),
  ratings     JSONB NOT NULL DEFAULT '{"offense":0,"defense":0,"rebound":0,"einsatz":0,"kondition":0}',
  active      BOOLEAN NOT NULL DEFAULT true,
  phone       TEXT,
  email       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Matches (ein Spieltag-Ergebnis)
CREATE TABLE IF NOT EXISTS matches (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_mode   INTEGER NOT NULL,   -- Spieler pro Team (2, 3, 4)
  team_count  INTEGER NOT NULL,   -- Anzahl Teams
  assign_mode TEXT NOT NULL,      -- 'random' | 'balanced'
  played_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Teams innerhalb eines Matches
CREATE TABLE IF NOT EXISTS match_teams (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id    UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  team_index  INTEGER NOT NULL,
  team_name   TEXT NOT NULL,
  score       INTEGER,
  result      TEXT CHECK (result IN ('win','loss','draw'))
);

-- Welcher Spieler war in welchem Team
CREATE TABLE IF NOT EXISTS match_players (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id    UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  team_id     UUID NOT NULL REFERENCES match_teams(id) ON DELETE CASCADE,
  player_id   UUID REFERENCES players(id) ON DELETE SET NULL  -- bleibt erhalten wenn Spieler gelöscht
);

-- ============================================================
-- RLS: Öffentlich (keine Auth erforderlich – alle lesen/schreiben)
-- Kann später durch Auth-Regeln eingeschränkt werden
-- ============================================================
ALTER TABLE players      ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches      ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_teams  ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_all" ON players       FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "public_all" ON matches       FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "public_all" ON match_teams   FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "public_all" ON match_players FOR ALL USING (true) WITH CHECK (true);

-- ============================================================
-- Realtime aktivieren (für Live-Updates ohne Seiten-Reload)
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE players;
ALTER PUBLICATION supabase_realtime ADD TABLE matches;
