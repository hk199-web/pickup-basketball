-- ============================================================
-- Pickup – Migration: Unentschieden wieder erlauben (Stand 12.10.2026)
-- Setzt migration-sicherheit-v1.1.sql voraus.
--
-- Regel: Die höchste Punktzahl gewinnt. Haben mehrere Teams die höchste
-- Punktzahl, sind diese Teams "draw" (Unentschieden), alle anderen "loss".
-- Beispiel 2 Teams 11:11 → beide draw. Alle übrigen Prüfungen bleiben.
-- ============================================================

-- Punkte prüfen (0–99, keine fehlenden Werte) und höchste Punktzahl liefern.
-- Gleichstand ist kein Fehler mehr.
CREATE OR REPLACE FUNCTION public.match_max_score(p_scores int[]) RETURNS int
LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
BEGIN
  IF p_scores IS NULL OR EXISTS (SELECT 1 FROM unnest(p_scores) s WHERE s IS NULL OR s < 0 OR s > 99) THEN
    RAISE EXCEPTION 'Bitte für jedes Team Punkte zwischen 0 und 99 eintragen';
  END IF;
  RETURN (SELECT max(s) FROM unnest(p_scores) s);
END $$;
REVOKE ALL ON FUNCTION public.match_max_score(int[]) FROM PUBLIC, anon, authenticated;

-- Ergebnis eines Teams aus seinen Punkten
CREATE OR REPLACE FUNCTION public.match_result(p_score int, p_max int, p_top int) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p_score < p_max THEN 'loss' WHEN p_top > 1 THEN 'draw' ELSE 'win' END;
$$;
REVOKE ALL ON FUNCTION public.match_result(int, int, int) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.save_match(
  p_game_mode int, p_team_count int, p_assign_mode text, p_season_id uuid, p_teams jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n int := jsonb_array_length(p_teams);
  v_scores int[];
  v_max int;
  v_top int;
  v_match uuid;
  v_team uuid;
  v_ids jsonb;
  v_all int;
  v_distinct int;
BEGIN
  IF p_game_mode NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Ungültiger Spielmodus'; END IF;
  IF v_n NOT BETWEEN 2 AND 4 OR v_n <> p_team_count THEN RAISE EXCEPTION 'Ungültige Anzahl Teams'; END IF;
  IF p_assign_mode NOT IN ('random','balanced','manual') THEN RAISE EXCEPTION 'Ungültiger Modus'; END IF;
  FOR i IN 0 .. v_n - 1 LOOP
    IF jsonb_array_length(coalesce(p_teams->i->'player_ids', '[]'::jsonb)) <> p_game_mode THEN
      RAISE EXCEPTION 'Team % braucht genau % Spieler', chr(65 + i), p_game_mode;
    END IF;
  END LOOP;
  SELECT count(*), count(DISTINCT pid) INTO v_all, v_distinct
    FROM jsonb_array_elements(p_teams) t, jsonb_array_elements_text(t->'player_ids') pid;
  IF v_all <> v_distinct THEN RAISE EXCEPTION 'Ein Spieler darf nur einmal pro Spiel vorkommen'; END IF;
  IF NOT public.is_admin()
     AND (SELECT count(*) FROM matches WHERE played_at > now() - interval '1 hour') >= 20 THEN
    RAISE EXCEPTION 'Zu viele Ergebnisse in kurzer Zeit – bitte später erneut versuchen';
  END IF;

  SELECT array_agg((t->>'score')::int ORDER BY o) INTO v_scores
    FROM jsonb_array_elements(p_teams) WITH ORDINALITY AS x(t, o);
  v_max := public.match_max_score(v_scores);
  SELECT count(*) INTO v_top FROM unnest(v_scores) s WHERE s = v_max;

  INSERT INTO matches (game_mode, team_count, assign_mode, season_id)
    VALUES (p_game_mode, p_team_count, p_assign_mode, p_season_id)
    RETURNING id INTO v_match;
  FOR i IN 0 .. v_n - 1 LOOP
    v_ids := p_teams->i->'player_ids';
    INSERT INTO match_teams (match_id, team_index, team_name, score, result)
      VALUES (v_match, i, 'Team ' || chr(65 + i), v_scores[i + 1],
              public.match_result(v_scores[i + 1], v_max, v_top))
      RETURNING id INTO v_team;
    INSERT INTO match_players (match_id, team_id, player_id)
      SELECT v_match, v_team, pid::uuid FROM jsonb_array_elements_text(v_ids) AS pid;
  END LOOP;
  RETURN v_match;
END $$;
REVOKE ALL ON FUNCTION public.save_match(int, int, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_match(int, int, text, uuid, jsonb) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_match(p_match_id uuid, p_teams jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scores int[];
  v_max int;
  v_top int;
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
  SELECT count(*) INTO v_top FROM unnest(v_scores) s WHERE s = v_max;

  DELETE FROM match_players WHERE match_id = p_match_id AND player_id IS NOT NULL;
  FOR v_t IN SELECT * FROM jsonb_array_elements(p_teams) LOOP
    v_team := (v_t->>'team_id')::uuid;
    UPDATE match_teams
       SET score = (v_t->>'score')::int,
           result = public.match_result((v_t->>'score')::int, v_max, v_top)
     WHERE id = v_team AND match_id = p_match_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Team gehört nicht zu diesem Spiel'; END IF;
    INSERT INTO match_players (match_id, team_id, player_id)
      SELECT p_match_id, v_team, pid::uuid
        FROM jsonb_array_elements_text(coalesce(v_t->'player_ids', '[]'::jsonb)) AS pid;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.update_match(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_match(uuid, jsonb) TO authenticated;
