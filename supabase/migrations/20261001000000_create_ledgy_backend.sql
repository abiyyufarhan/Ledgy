-- Ledgy phase 5: local schema mirrored in Supabase/PostgreSQL.
-- IDs supplied by the offline app are retained; server-generated IDs are UUID v4.
-- Money is integer rupiah. timestamptz preserves instants from UTC device payloads.
begin;

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  initial_balance bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  is_dirty boolean not null default true,
  constraint accounts_user_id_id_key unique (user_id, id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  kind text not null default 'expense',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  is_dirty boolean not null default true,
  constraint categories_kind_check check (kind in ('income', 'expense')),
  constraint categories_user_id_id_key unique (user_id, id)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null,
  amount bigint not null,
  account_id uuid not null,
  to_account_id uuid,
  category_id uuid,
  note text,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  is_dirty boolean not null default true,
  constraint transactions_type_check check (type in ('income', 'expense', 'transfer')),
  constraint transactions_amount_check check (amount >= 0),
  constraint transactions_transfer_check check (
    (type = 'transfer' and to_account_id is not null and account_id <> to_account_id)
    or (type <> 'transfer' and to_account_id is null)
  ),
  -- Including user_id in each FK prevents referencing another user's data.
  constraint transactions_account_owner_fkey foreign key (user_id, account_id)
    references public.accounts (user_id, id),
  constraint transactions_target_owner_fkey foreign key (user_id, to_account_id)
    references public.accounts (user_id, id),
  constraint transactions_category_owner_fkey foreign key (user_id, category_id)
    references public.categories (user_id, id)
);

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category_id uuid not null,
  amount bigint not null,
  -- Kept as timestamptz to match Drift DateTime, including local month start
  -- converted to UTC (e.g. October 1 00:00 WIB = September 30 17:00 UTC).
  month_start timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  is_dirty boolean not null default true,
  constraint budgets_amount_check check (amount >= 0),
  constraint budgets_category_owner_fkey foreign key (user_id, category_id)
    references public.categories (user_id, id)
);

create table public.recurring_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null,
  amount bigint not null,
  account_id uuid not null,
  to_account_id uuid,
  category_id uuid,
  note text,
  frequency text not null,
  "interval" integer not null default 1,
  next_occurrence_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  is_dirty boolean not null default true,
  constraint recurring_rules_type_check check (type in ('income', 'expense', 'transfer')),
  constraint recurring_rules_amount_check check (amount >= 0),
  constraint recurring_rules_frequency_check check (frequency in ('daily', 'weekly', 'monthly')),
  constraint recurring_rules_interval_check check ("interval" > 0),
  constraint recurring_rules_transfer_check check (
    (type = 'transfer' and to_account_id is not null and account_id <> to_account_id)
    or (type <> 'transfer' and to_account_id is null)
  ),
  constraint recurring_rules_account_owner_fkey foreign key (user_id, account_id)
    references public.accounts (user_id, id),
  constraint recurring_rules_target_owner_fkey foreign key (user_id, to_account_id)
    references public.accounts (user_id, id),
  constraint recurring_rules_category_owner_fkey foreign key (user_id, category_id)
    references public.categories (user_id, id)
);

-- ALWAYS replace a client-supplied updated_at, on insert and update/upsert.
-- SECURITY INVOKER keeps the trigger in the caller's privilege context.
create function public.ledgy_set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function public.ledgy_set_updated_at() from public, anon;
grant execute on function public.ledgy_set_updated_at() to authenticated;

-- accounts: owner-only SELECT / INSERT / UPDATE / DELETE.
alter table public.accounts enable row level security;

-- Clear Supabase's default grants, then expose only row-level CRUD to logged-in users.
-- No client receives TRUNCATE, REFERENCES, or TRIGGER privileges.
revoke all on table public.accounts from public, anon, authenticated;
grant select, insert, update, delete on table public.accounts to authenticated;

create policy accounts_select_own on public.accounts
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy accounts_insert_own on public.accounts
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy accounts_update_own on public.accounts
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy accounts_delete_own on public.accounts
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger accounts_set_updated_at
  before insert or update on public.accounts
  for each row execute function public.ledgy_set_updated_at();

-- Not partial: sync must also retrieve soft-deleted rows (tombstones).
create index accounts_user_id_updated_at_idx
  on public.accounts (user_id, updated_at);

-- categories: owner-only SELECT / INSERT / UPDATE / DELETE.
alter table public.categories enable row level security;

-- Clear Supabase's default grants, then expose only row-level CRUD to logged-in users.
-- No client receives TRUNCATE, REFERENCES, or TRIGGER privileges.
revoke all on table public.categories from public, anon, authenticated;
grant select, insert, update, delete on table public.categories to authenticated;

create policy categories_select_own on public.categories
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy categories_insert_own on public.categories
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy categories_update_own on public.categories
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy categories_delete_own on public.categories
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger categories_set_updated_at
  before insert or update on public.categories
  for each row execute function public.ledgy_set_updated_at();

-- Not partial: sync must also retrieve soft-deleted rows (tombstones).
create index categories_user_id_updated_at_idx
  on public.categories (user_id, updated_at);

-- transactions: owner-only SELECT / INSERT / UPDATE / DELETE.
alter table public.transactions enable row level security;

-- Clear Supabase's default grants, then expose only row-level CRUD to logged-in users.
-- No client receives TRUNCATE, REFERENCES, or TRIGGER privileges.
revoke all on table public.transactions from public, anon, authenticated;
grant select, insert, update, delete on table public.transactions to authenticated;

create policy transactions_select_own on public.transactions
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy transactions_insert_own on public.transactions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy transactions_update_own on public.transactions
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy transactions_delete_own on public.transactions
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger transactions_set_updated_at
  before insert or update on public.transactions
  for each row execute function public.ledgy_set_updated_at();

-- Not partial: sync must also retrieve soft-deleted rows (tombstones).
create index transactions_user_id_updated_at_idx
  on public.transactions (user_id, updated_at);

-- budgets: owner-only SELECT / INSERT / UPDATE / DELETE.
alter table public.budgets enable row level security;

-- Clear Supabase's default grants, then expose only row-level CRUD to logged-in users.
-- No client receives TRUNCATE, REFERENCES, or TRIGGER privileges.
revoke all on table public.budgets from public, anon, authenticated;
grant select, insert, update, delete on table public.budgets to authenticated;

create policy budgets_select_own on public.budgets
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy budgets_insert_own on public.budgets
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy budgets_update_own on public.budgets
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy budgets_delete_own on public.budgets
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger budgets_set_updated_at
  before insert or update on public.budgets
  for each row execute function public.ledgy_set_updated_at();

-- Not partial: sync must also retrieve soft-deleted rows (tombstones).
create index budgets_user_id_updated_at_idx
  on public.budgets (user_id, updated_at);

-- recurring_rules: owner-only SELECT / INSERT / UPDATE / DELETE.
alter table public.recurring_rules enable row level security;

-- Clear Supabase's default grants, then expose only row-level CRUD to logged-in users.
-- No client receives TRUNCATE, REFERENCES, or TRIGGER privileges.
revoke all on table public.recurring_rules from public, anon, authenticated;
grant select, insert, update, delete on table public.recurring_rules to authenticated;

create policy recurring_rules_select_own on public.recurring_rules
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy recurring_rules_insert_own on public.recurring_rules
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy recurring_rules_update_own on public.recurring_rules
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy recurring_rules_delete_own on public.recurring_rules
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger recurring_rules_set_updated_at
  before insert or update on public.recurring_rules
  for each row execute function public.ledgy_set_updated_at();

-- Not partial: sync must also retrieve soft-deleted rows (tombstones).
create index recurring_rules_user_id_updated_at_idx
  on public.recurring_rules (user_id, updated_at);

-- RLS intentionally does not filter deleted_at: the owner can synchronize deletions.
-- Normal app lists exclude deleted rows; incremental sync includes them.
commit;
