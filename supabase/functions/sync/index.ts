import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleSync, type Db } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const db: Db = {
  async getDeviceHash(expected: string) {
    const { data, error } = await supabase.from("devices").select("channel").eq("device_key_hash", expected).maybeSingle();
    return { channel: (data as { channel?: string } | null)?.channel ?? null, error: error ? error.message : null };
  },
  async getMatchDevice(matchId) {
    const { data, error } = await supabase.from("matches").select("device_id").eq("match_id", matchId).maybeSingle();
    return { deviceId: (data as { device_id?: string } | null)?.device_id ?? null, error: error ? error.message : null };
  },
  async upsertMatch(matchId, deviceId, config, startedAt, status, channel) {
    const { error } = await supabase.from("matches").upsert(
      { match_id: matchId, device_id: deviceId, config, started_at: startedAt, status, channel },
      { onConflict: "match_id" },
    );
    return { error: error ? error.message : null };
  },
  async upsertEvents(matchId, events) {
    const rows = events.map((e) => ({
      id: `${matchId}:${e.sequence}`,
      match_id: matchId,
      sequence: e.sequence,
      type: e.type,
      arg: e.arg ?? 0,
      prev_me: e.prevMe ?? null,
      prev_opp: e.prevOpp ?? null,
      ts: e.ts ?? null,
    }));
    // Idempotence : doublons ignorés (UNIQUE (match_id, sequence), spec sync §7).
    const { error } = await supabase.from("events")
      .upsert(rows, { onConflict: "match_id,sequence", ignoreDuplicates: true });
    return { error: error ? error.message : null };
  },
  async upsertState(matchId, snapshot, config) {
    const { error } = await supabase.from("match_state").upsert({
      match_id: matchId,
      status: snapshot.status,
      current_set: snapshot.currentSet,
      score_me: snapshot.scoreMe,
      score_opp: snapshot.scoreOpp,
      sets_me: snapshot.setsMe,
      sets_opp: snapshot.setsOpp,
      last_sequence: snapshot.lastSequence,
      config,
    }, { onConflict: "match_id" });
    return { error: error ? error.message : null };
  },
};

Deno.serve((req: Request) => handleSync(req, db));
