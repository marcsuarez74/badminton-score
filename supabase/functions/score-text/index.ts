import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleScoreText, type Db, type ScoreRow } from "./handler.ts";

// Lecture publique (RLS SELECT anon) — même posture que l'overlay.
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!,
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
};

Deno.serve((req: Request) => handleScoreText(req, db));
