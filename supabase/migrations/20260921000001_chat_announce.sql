-- Annonceur automatique du score dans le chat Twitch (StreamElements).
-- devices.se_channel_id : id de canal StreamElements (décodé de la JWT API
--   du compte) ; NULL = pas d'annonce auto pour ce canal.
-- devices.name1/name2 : noms affichés dans les annonces (défaut MOI/LUI,
--   éditable par canal — l'overlay garde ses noms en paramètre d'URL).
-- chat_announce : dernier texte annoncé par canal (dédoublonnage) ; aucune
--   policy RLS → accès service-role uniquement (l'Edge Function du cron).
alter table devices
  add column se_channel_id text,
  add column name1 text not null default 'MOI',
  add column name2 text not null default 'LUI';

create table chat_announce (
  channel    text primary key,
  last_text  text not null,
  updated_at timestamptz not null default now()
);
alter table chat_announce enable row level security;
