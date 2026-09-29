-- ============================================================
-- Pickup – Migration: Saisons
-- Im Supabase SQL Editor ausführen (Dashboard → SQL Editor → New Query)
-- ============================================================

-- Saisons-Tabelle
CREATE TABLE IF NOT EXISTS seasons (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,                    -- z.B. "Indoor 26/27"
  kind        TEXT CHECK (kind IN ('indoor','outdoor')),
  is_active   BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Matches einer Saison zuordnen
ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS season_id UUID REFERENCES seasons(id) ON DELETE SET NULL;

-- RLS
ALTER TABLE seasons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_all" ON seasons;
CREATE POLICY "public_all" ON seasons FOR ALL USING (true) WITH CHECK (true);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE seasons;

-- Zwei Start-Saisons anlegen
INSERT INTO seasons (name, kind, is_active) VALUES
  ('Indoor 26/27', 'indoor',  true),
  ('Outdoor 26',   'outdoor', false);
