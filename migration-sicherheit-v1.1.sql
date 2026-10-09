-- ============================================================
-- Pickup – Migration: Sicherheitsbefunde aus Prüfbericht PB-SEC v1.0 (08.10.2026)
-- Stand 10.10.2026. Setzt migration-admin-schutz.sql voraus.
--
-- B01  Ratings nur ganze Zahlen 0–5 (kein Text/HTML mehr speicherbar)
-- B02  Plausibilität + Mengenbremse für Besucher
-- B03  TRUNCATE/TRIGGER/REFERENCES für anon/authenticated entzogen
-- B07  Echte Namen nur für Admin lesbar, öffentlich nur Spitznamen
-- ============================================================

-- ---------- B03: Rechte, die niemand braucht ----------
REVOKE TRUNCATE, TRIGGER, REFERENCES
  ON public.players, public.matches, public.match_teams, public.match_players, public.seasons, public.admins
  FROM anon, authenticated;
-- auch für künftige Tabellen
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLES FROM anon, authenticated;

-- ---------- B01/B02: Eingaberegeln in der Datenbank ----------
CREATE OR REPLACE FUNCTION public.valid_ratings(r jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT coalesce(jsonb_typeof(r) = 'object' AND NOT EXISTS (
    SELECT 1 FROM jsonb_each(r) e
     WHERE e.key NOT IN ('offense','defense','rebound','einsatz','kondition')
        OR jsonb_typeof(e.value) <> 'number'
        OR (e.value #>> '{}')::numeric NOT IN (0,1,2,3,4,5)
  ), false);
$$;

ALTER TABLE public.players
  ADD CONSTRAINT players_ratings_valid CHECK (public.valid_ratings(ratings)),
  ADD CONSTRAINT players_name_len      CHECK (char_length(btrim(name)) BETWEEN 1 AND 40),
  ADD CONSTRAINT players_nickname_len  CHECK (char_length(btrim(nickname)) BETWEEN 1 AND 40);
-- Spitzname ist Pflicht, weil er öffentlich der einzige sichtbare Name ist (B07)
ALTER TABLE public.players ALTER COLUMN nickname SET NOT NULL;

ALTER TABLE public.seasons
  ADD CONSTRAINT seasons_name_len CHECK (char_length(btrim(name)) BETWEEN 1 AND 60);
ALTER TABLE public.match_teams
  ADD CONSTRAINT match_teams_score_range CHECK (score IS NULL OR score BETWEEN 0 AND 99);

-- ---------- B02 + B07: Spaltenrechte für Besucher ----------
-- Anlegen: nur diese Felder; id und created_at vergibt die Datenbank
REVOKE INSERT ON public.players FROM anon;
GRANT  INSERT (name, nickname, position, ratings, active) ON public.players TO anon;
-- Lesen: alles außer dem echten Namen
REVOKE SELECT ON public.players FROM anon;
GRANT  SELECT (id, nickname, position, ratings, active, created_at) ON public.players TO anon;

-- ---------- B02: Mengenbremse neue Spieler (10 pro Stunde, Admin ausgenommen) ----------
CREATE OR REPLACE FUNCTION public.players_insert_limit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin()
     AND (SELECT count(*) FROM public.players WHERE created_at > now() - interval '1 hour') >= 10 THEN
    RAISE EXCEPTION 'Zu viele neue Spieler in kurzer Zeit – bitte später erneut versuchen';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.players_insert_limit() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS players_insert_limit ON public.players;
CREATE TRIGGER players_insert_limit BEFORE INSERT ON public.players
  FOR EACH ROW EXECUTE FUNCTION public.players_insert_limit();

-- ---------- B02: Punkte 0–99 ----------
CREATE OR REPLACE FUNCTION public.match_max_score(p_scores int[]) RETURNS int
LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE v_max int;
BEGIN
  IF p_scores IS NULL OR EXISTS (SELECT 1 FROM unnest(p_scores) s WHERE s IS NULL OR s < 0 OR s > 99) THEN
    RAISE EXCEPTION 'Bitte für jedes Team Punkte zwischen 0 und 99 eintragen';
  END IF;
  SELECT max(s) INTO v_max FROM unnest(p_scores) s;
  IF (SELECT count(*) FROM unnest(p_scores) s WHERE s = v_max) > 1 THEN
    RAISE EXCEPTION 'Gleichstand – es braucht einen Sieger mit den meisten Punkten';
  END IF;
  RETURN v_max;
END $$;
REVOKE ALL ON FUNCTION public.match_max_score(int[]) FROM PUBLIC, anon, authenticated;

-- ---------- B02: Ergebnis speichern mit Plausibilität und Mengenbremse ----------
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
  v_all int;
  v_distinct int;
BEGIN
  IF p_game_mode NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Ungültiger Spielmodus'; END IF;
  IF v_n NOT BETWEEN 2 AND 4 OR v_n <> p_team_count THEN RAISE EXCEPTION 'Ungültige Anzahl Teams'; END IF;
  IF p_assign_mode NOT IN ('random','balanced','manual') THEN RAISE EXCEPTION 'Ungültiger Modus'; END IF;

  -- Jedes Team genau so groß wie der Modus, jeder Spieler nur einmal im Spiel
  FOR i IN 0 .. v_n - 1 LOOP
    IF jsonb_array_length(coalesce(p_teams->i->'player_ids', '[]'::jsonb)) <> p_game_mode THEN
      RAISE EXCEPTION 'Team % braucht genau % Spieler', chr(65 + i), p_game_mode;
    END IF;
  END LOOP;
  SELECT count(*), count(DISTINCT pid) INTO v_all, v_distinct
    FROM jsonb_array_elements(p_teams) t, jsonb_array_elements_text(t->'player_ids') pid;
  IF v_all <> v_distinct THEN RAISE EXCEPTION 'Ein Spieler darf nur einmal pro Spiel vorkommen'; END IF;

  -- Mengenbremse: höchstens 20 Spiele pro Stunde (Admin ausgenommen)
  IF NOT public.is_admin()
     AND (SELECT count(*) FROM matches WHERE played_at > now() - interval '1 hour') >= 20 THEN
    RAISE EXCEPTION 'Zu viele Ergebnisse in kurzer Zeit – bitte später erneut versuchen';
  END IF;

  SELECT array_agg((t->>'score')::int ORDER BY o) INTO v_scores
    FROM jsonb_array_elements(p_teams) WITH ORDINALITY AS x(t, o);
  v_max := public.match_max_score(v_scores);

  INSERT INTO matches (game_mode, team_count, assign_mode, season_id)
    VALUES (p_game_mode, p_team_count, p_assign_mode, p_season_id)
    RETURNING id INTO v_match;

  FOR i IN 0 .. v_n - 1 LOOP
    v_ids := p_teams->i->'player_ids';
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

-- ---------- update_match: zusätzlich jeder Spieler nur einmal ----------
CREATE OR REPLACE FUNCTION public.update_match(p_match_id uuid, p_teams jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scores int[];
  v_max int;
  v_t jsonb;
  v_team uuid;
  v_all int;
  v_distinct int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Nur für Admins'; END IF;

  SELECT count(*), count(DISTINCT pid) INTO v_all, v_distinct
    FROM jsonb_array_elements(p_teams) t, jsonb_array_elements_text(coalesce(t->'player_ids','[]'::jsonb)) pid;
  IF v_all <> v_distinct THEN RAISE EXCEPTION 'Ein Spieler darf nur einmal pro Spiel vorkommen'; END IF;

  SELECT array_agg((t->>'score')::int ORDER BY o) INTO v_scores
    FROM jsonb_array_elements(p_teams) WITH ORDINALITY AS x(t, o);
  v_max := public.match_max_score(v_scores);

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
