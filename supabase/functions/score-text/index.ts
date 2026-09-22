import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleScoreText, type Db, type ScoreRow } from "./handler.ts";

// Service role : matches/match_state sont lisibles anon (RLS SELECT), mais
// devices porte le hash de la clé (jamais exposé) — getNames passe donc par
// le service role et n'exporte que les noms publics du canal.
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function toScoreRow(m: Record<string, unknown> | null): ScoreRow | null {
  if (!m) return null;
  const ms = m.match_state as Record<string, unknown> | undefined;
  if (!ms) return null;
  return {
    status: String(ms.status),
    currentSet: Number(ms.current_set),
    scoreMe: Number(ms.score_me),
    scoreOpp: Number(ms.score_opp),
    setsMe: Number(ms.sets_me),
    setsOpp: Number(ms.sets_opp),
    config: ms.config as ScoreRow["config"] ?? null,
  };
}

const db: Db = {
  async latestMatch(channel, activeOnly) {
    let req = supabase.from("matches")
      .select("started_at, match_state!inner(status, current_set, score_me, score_opp, sets_me, sets_opp, config)")
      .eq("channel", channel)
      .order("started_at", { ascending: false, nullsFirst: false })
      .limit(1);
    if (activeOnly) req = req.eq("match_state.status", "active");
    const { data, error } = await req;
    if (error || !data || data.length === 0) return null;
    return toScoreRow(data[0]);
  },
  async getNames(channel) {
    const { data, error } = await supabase.from("devices")
      .select("format, name1, name1b, name2, name2b").eq("channel", channel).maybeSingle();
    if (error || !data) return null;
    return {
      format: String(data.format ?? "simple"),
      name1: String(data.name1 ?? ""),
      name1b: String(data.name1b ?? ""),
      name2: String(data.name2 ?? ""),
      name2b: String(data.name2b ?? ""),
    };
  },
};

Deno.serve((req: Request) => handleScoreText(req, db));
