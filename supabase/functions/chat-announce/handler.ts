// Edge Function chat-announce — annonceur automatique du score dans le chat
// Twitch via l'API StreamElements (kappa v2 chat). Appelée par un cron
// Supabase (pg_cron + pg_net) toutes les 30 s. Logique pure testable :
// pour chaque canal configuré (devices.se_channel_id), on calcule le texte
// du score courant (même format que !score) et on le poste s'il a changé
// depuis la dernière annonce. Aucun message d'attente : on n'annonce que
// s'il y a un match. En cas d'échec d'envoi, last_text n'est pas mis à
// jour → retentative naturelle au prochain passage.
import { formatScore, type ScoreRow } from "../score-text/handler.ts";

export type { ScoreRow };

export interface ChannelCfg {
  channel: string;
  seChannelId: string | null;
  name1: string;
  name2: string;
}

export interface AnnounceDb {
  // Canaux à traiter (devices avec/sans se_channel_id).
  channels(): Promise<ChannelCfg[]>;
  // Match actif le plus récent du canal ; fallback : le plus récent tout statut.
  latestMatch(channel: string, activeOnly: boolean): Promise<ScoreRow | null>;
  lastAnnounced(channel: string): Promise<string | null>;
  saveAnnounced(channel: string, text: string): Promise<void>;
}

export interface ChatSender {
  send(seChannelId: string, message: string): Promise<void>;
}

export interface AnnounceEnv {
  // Si défini, la requête doit porter ?key=<valeur> (protège le endpoint
  // appelé par le cron sans JWT).
  announceKey?: string;
}

function sane(row: ScoreRow): boolean {
  return [row.currentSet, row.scoreMe, row.scoreOpp, row.setsMe, row.setsOpp].every((v) => v !== null);
}

export async function handleChatAnnounce(
  req: Request,
  db: AnnounceDb,
  sender: ChatSender,
  env: AnnounceEnv = {},
): Promise<Response> {
  const u = new URL(req.url);
  if (env.announceKey !== undefined && u.searchParams.get("key") !== env.announceKey) {
    return new Response("unauthorized", { status: 401 });
  }

  const announced: string[] = [];
  const errors: string[] = [];
  for (const cfg of await db.channels()) {
    if (!cfg.seChannelId) continue;
    const active = await db.latestMatch(cfg.channel, true);
    const current = active && sane(active) ? active : null;
    const fallback = current ? null : await db.latestMatch(cfg.channel, false);
    const row = current ?? (fallback && sane(fallback) ? fallback : null);
    if (!row) continue;

    const text = formatScore(row, cfg.name1, cfg.name2);
    const last = await db.lastAnnounced(cfg.channel);
    if (text === last) continue;

    try {
      await sender.send(cfg.seChannelId, text);
      await db.saveAnnounced(cfg.channel, text);
      announced.push(cfg.channel);
    } catch {
      errors.push(cfg.channel);
    }
  }

  return new Response(JSON.stringify({ announced, errors }), {
    status: 200,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
