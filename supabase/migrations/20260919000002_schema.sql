-- Schéma Phase 4a (spec sync §12) — montre = source de vérité (ADR-007).
create table matches (
  match_id   text primary key,
  device_id  text not null,
  channel    text not null default 'marc',
  config     jsonb not null,
  status     text not null default 'active' check (status in ('active','finished','archived')),
  started_at bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table events (
  id        text primary key,
  match_id  text not null references matches(match_id),
  sequence  int  not null check (sequence > 0),
  type      int  not null check (type between 0 and 5),  -- 0=POINT_ME 1=POINT_OPPONENT 2=SET_FINISHED 3=SET_CHANGED 4=MATCH_FINISHED 5=UNDO(réservé)
  arg       int  not null default 0,
  prev_me   int,
  prev_opp  int,
  ts        bigint,
  created_at timestamptz not null default now(),
  unique (match_id, sequence)
);

create table match_state (
  match_id      text primary key references matches(match_id),
  status        text not null check (status in ('active','set_result','match_finished')),
  current_set   int  not null default 1,
  score_me      int  not null default 0,
  score_opp     int  not null default 0,
  sets_me       int  not null default 0,
  sets_opp      int  not null default 0,
  last_sequence int  not null default 0,
  config        jsonb not null,
  updated_at    timestamptz not null default now()
);

create table devices (
  id              smallint primary key default 1,
  device_key_hash text not null,
  label           text,
  created_at      timestamptz not null default now()
);
insert into devices (device_key_hash, label) values ('2f4a5184b8f7f6a5d6d6b39e3c46641bf746b7933a6160f26347cd9a5006652d', 'epix Pro 51 mm');

-- Lecture seule publique (overlay) ; écriture = Edge Function service role.
-- Piège officiel : les policies ne révoquent pas les grants → REVOKE d'abord.
revoke all on matches, events, match_state from anon, authenticated;
grant select on matches, events, match_state to anon;
alter table matches     enable row level security;
alter table events      enable row level security;
alter table match_state enable row level security;
create policy "public read matches"     on matches     for select to anon using (true);
create policy "public read events"      on events      for select to anon using (true);
create policy "public read state"       on match_state for select to anon using (true);

drop table if exists poc_events;

alter publication supabase_realtime add table matches, events, match_state;
