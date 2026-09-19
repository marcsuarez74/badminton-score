-- POC Phase 4a : table jetable pour prouver montre -> GCM -> Edge Function -> DB.
-- Supprimée par la migration du schéma complet (Task 4).
create table poc_events (
  id bigint generated always as identity primary key,
  payload jsonb not null,
  created_at timestamptz not null default now()
);
