-- ============================================================
-- Pickup – Migration: Admin-Schutz (Stand 02.10.2026)
--
-- Ohne Anmeldung erlaubt: alles lesen, Spieler aktiv/inaktiv schalten,
-- neue Spieler anlegen, Ergebnisse eintragen (nur über save_match).
-- Nur Admin (angemeldet + in Tabelle admins): alles andere –
-- löschen, Ergebnisse korrigieren, Saisons, Spieler/Ratings ändern.
--
-- Admin-Konto anlegen: Supabase-Dashboard → Authentication → Users →
-- Add user. Danach die user_id in die Tabelle admins eintragen.
-- ============================================================

-- ---------- Admin-Liste ----------
CREATE TABLE IF NOT EXISTS public.admins (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admins_select_own ON public.admins;
CREATE POLICY admins_select_own ON public.admins
  FOR SELECT TO authenticated USING (user_id = auth.uid());
-- Eintragen/Entfernen nur über den SQL Editor, nie über die App
REVOKE ALL ON public.admins FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.admins FROM authenticated;

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid());
$$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

-- ---------- Alte Regel "jeder darf alles" entfernen ----------
DROP POLICY IF EXISTS "public_all" ON public.players;
DROP POLICY IF EXISTS "public_all" ON public.matches;
DROP POLICY IF EXISTS "public_all" ON public.match_teams;
DROP POLICY IF EXISTS "public_all" ON public.match_players;
DROP POLICY IF EXISTS "public_all" ON public.seasons;

-- ---------- Lesen: alle ----------
CREATE POLICY read_all ON public.players       FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY read_all ON public.matches       FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY read_all ON public.match_teams   FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY read_all ON public.match_players FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY read_all ON public.seasons       FOR SELECT TO anon, authenticated USING (true);

-- ---------- Admin: alles ----------
CREATE POLICY admin_all ON public.players       FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY admin_all ON public.matches       FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY admin_all ON public.match_teams   FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY admin_all ON public.match_players FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY admin_all ON public.seasons       FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------- Ohne Anmeldung: Spieltag-Alltag ----------
-- Neue Spieler anlegen
CREATE POLICY anon_insert ON public.players FOR INSERT TO anon WITH CHECK (true);
-- Aktiv/inaktiv schalten – per Spaltenrecht nur die Spalte "active"
CREATE POLICY anon_update_active ON public.players FOR UPDATE TO anon USING (true) WITH CHECK (true);
REVOKE UPDATE ON public.players FROM anon;
GRANT UPDATE (active) ON public.players TO anon;
-- Direktes Schreiben in Spiel-Tabellen nur über die Funktionen unten
REVOKE INSERT, UPDATE, DELETE ON public.matches, public.match_teams, public.match_players, public.seasons FROM anon;
REVOKE DELETE ON public.players FROM anon;

-- ---------- Hilfsfunktion: Punkte prüfen, Sieger bestimmen ----------
-- Höchste Punktzahl gewinnt; fehlende Punkte oder Gleichstand an der Spitze → Fehler
CREATE OR REPLACE FUNCTION public.match_max_score(p_scores int[]) RETURNS int
LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE v_max int;
BEGIN
  IF p_scores IS NULL OR EXISTS (SELECT 1 FROM unnest(p_scores) s WHERE s IS NULL OR s < 0 OR s > 999) THEN
    RAISE EXCEPTION 'Bitte für jedes Team die Punkte eintragen';
  END IF;
  SELECT max(s) INTO v_max FROM unnest(p_scores) s;
  IF (SELECT count(*) FROM unnest(p_scores) s WHERE s = v_max) > 1 THEN
    RAISE EXCEPTION 'Gleichstand – es braucht einen Sieger mit den meisten Punkten';
  END IF;
  RETURN v_max;
END $$;
REVOKE ALL ON FUNCTION public.match_max_score(int[]) FROM PUBLIC, anon, authenticated;

-- ---------- Ergebnis speichern (alle) – alles oder nichts ----------
-- p_teams: [{"score":11,"player_ids":["uuid",…]}, …] in Team-Reihenfolge A, B, …
CREATE OR REPLACE FUNCTION public.save_match(
  p_game_mode int, p_team_count int, p_assign_mode text, p_season_id uuid, p_teams jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n int := jsonb_array_length(p_teams);
  v_scores int[];
  v_max int;
  v_match uuid;
  v_team uuid;
  v_ids jsonb;
BEGIN
  IF v_n NOT BETWEEN 2 AND 4 OR v_n <> p_team_count THEN RAISE EXCEPTION 'Ungültige Anzahl Teams'; END IF;
  IF p_game_mode NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Ungültiger Spielmodus'; END IF;
  IF p_assign_mode NOT IN ('random','balanced','manual') THEN RAISE EXCEPTION 'Ungültiger Modus'; END IF;

  SELECT array_agg((t->>'score')::int ORDER BY o) INTO v_scores
    FROM jsonb_array_elements(p_teams) WITH ORDINALITY AS x(t, o);
  v_max := public.match_max_score(v_scores);

  INSERT INTO matches (game_mode, team_count, assign_mode, season_id)
    VALUES (p_game_mode, p_team_count, p_assign_mode, p_season_id)
    RETURNING id INTO v_match;

  FOR i IN 0 .. v_n - 1 LOOP
    v_ids := coalesce(p_teams->i->'player_ids', '[]'::jsonb);
    IF jsonb_array_length(v_ids) NOT BETWEEN 1 AND p_game_mode THEN
      RAISE EXCEPTION 'Ungültige Spielerzahl in Team %', chr(65 + i);
    END IF;
    INSERT INTO match_teams (match_id, team_index, team_name, score, result)
      VALUES (v_match, i, 'Team ' || chr(65 + i), v_scores[i + 1],
              CASE WHEN v_scores[i + 1] = v_max THEN 'win' ELSE 'loss' END)
      RETURNING id INTO v_team;
    INSERT INTO match_players (match_id, team_id, player_id)
      SELECT v_match, v_team, pid::uuid FROM jsonb_array_elements_text(v_ids) AS pid;
  END LOOP;
  RETURN v_match;
END $$;
REVOKE ALL ON FUNCTION public.save_match(int, int, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_match(int, int, text, uuid, jsonb) TO anon, authenticated;

-- ---------- Ergebnis korrigieren (nur Admin) – alles oder nichts ----------
-- p_teams: [{"team_id":"uuid","score":11,"player_ids":["uuid",…]}, …]
CREATE OR REPLACE FUNCTION public.update_match(p_match_id uuid, p_teams jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scores int[];
  v_max int;
  v_t jsonb;
  v_team uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Nur für Admins'; END IF;

  SELECT array_agg((t->>'score')::int ORDER BY o) INTO v_scores
    FROM jsonb_array_elements(p_teams) WITH ORDINALITY AS x(t, o);
  v_max := public.match_max_score(v_scores);

  -- Zuordnungen neu setzen; Einträge gelöschter Spieler (player_id = null) bleiben
  DELETE FROM match_players WHERE match_id = p_match_id AND player_id IS NOT NULL;

  FOR v_t IN SELECT * FROM jsonb_array_elements(p_teams) LOOP
    v_team := (v_t->>'team_id')::uuid;
    UPDATE match_teams
       SET score = (v_t->>'score')::int,
           result = CASE WHEN (v_t->>'score')::int = v_max THEN 'win' ELSE 'loss' END
     WHERE id = v_team AND match_id = p_match_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Team gehört nicht zu diesem Spiel'; END IF;
    INSERT INTO match_players (match_id, team_id, player_id)
      SELECT p_match_id, v_team, pid::uuid
        FROM jsonb_array_elements_text(coalesce(v_t->'player_ids', '[]'::jsonb)) AS pid;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.update_match(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_match(uuid, jsonb) TO authenticated;

-- Admin eintragen (einmalig, im SQL Editor):
-- INSERT INTO public.admins (user_id) SELECT id FROM auth.users WHERE email = '<admin-email>';
