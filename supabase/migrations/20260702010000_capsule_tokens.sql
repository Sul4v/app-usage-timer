-- Live Activity push tokens, one per device install. Not user-scoped: the
-- capsule must work before/without sign-in, so rows are keyed by an anonymous
-- device_id. Only the Edge Functions (service role) touch this table, so RLS
-- is on with no policies — the anon/authenticated roles get no access.
create table public.capsule_tokens (
  device_id text primary key,
  token text not null,
  updated_at timestamptz not null default now()
);

alter table public.capsule_tokens enable row level security;
