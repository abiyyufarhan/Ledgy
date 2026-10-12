// Local-only PostgreSQL verification. No project URL, password, or key is read.
// Install the temporary engine as described in ../README.md.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';

const require = createRequire(new URL('../../.dart_tool/phase5_validation/package.json', import.meta.url));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite(); // In-memory PostgreSQL: never connects to hosted Supabase.
const tables = ['accounts', 'categories', 'transactions', 'budgets', 'recurring_rules'];
const alice = '11111111-1111-4111-8111-111111111111';
const bob = '22222222-2222-4222-8222-222222222222';
const fixtures = {};
let checks = 0;

function equal(actual, expected, label) {
  assert.deepEqual(actual, expected, label);
  checks++;
}
async function denied(sql, parameters, code, label) {
  let actual = 'NO_ERROR';
  try { await db.query(sql, parameters); } catch (error) { actual = error.code; }
  equal(actual, code, label);
}
async function authenticate(id) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims', $1, false)",
    [JSON.stringify({ sub: id, role: 'authenticated' })]);
  await db.exec('set role authenticated');
}
function fields(table, owner) {
  const f = fixtures[owner];
  return {
    accounts: { name: 'Test account', initial_balance: '3000000000' },
    categories: { name: 'Test category', kind: 'expense' },
    transactions: { type: 'expense', amount: 100, account_id: f?.accounts?.id,
      category_id: f?.categories?.id, occurred_at: '2026-10-01T15:30:00Z' },
    budgets: { amount: 1000, category_id: f?.categories?.id,
      month_start: '2026-09-30T17:00:00Z' },
    recurring_rules: { type: 'expense', amount: 50, account_id: f?.accounts?.id,
      category_id: f?.categories?.id, frequency: 'monthly', interval: 1,
      next_occurrence_at: '2026-10-31T15:30:00Z' },
  }[table];
}
function insert(table, data, upsert = false) {
  const keys = Object.keys(data);
  const columns = keys.map(k => '"' + k + '"').join(', ');
  const placeholders = keys.map((_, i) => '$' + (i + 1)).join(', ');
  const conflict = upsert ? 'on conflict (id) do update set updated_at = excluded.updated_at, is_dirty = false' : '';
  return [
    'insert into public.' + table + ' (' + columns + ') values (' + placeholders + ') ' +
      conflict + ' returning *, updated_at = now() as server_clock_matches',
    Object.values(data),
  ];
}
async function create(table, owner, extra = {}) {
  const args = insert(table, { ...fields(table, owner), updated_at: '2099-01-01T00:00:00Z', ...extra });
  return (await db.query(...args)).rows[0];
}

try {
  // Only the minimal Supabase roles/Auth objects needed to exercise PostgreSQL
  // RLS are emulated. Hosted JWT validation and email delivery are not emulated.
  await db.exec(`
    create role anon nologin nosuperuser nobypassrls;
    create role authenticated nologin nosuperuser nobypassrls;
    create schema auth;
    create table auth.users (id uuid primary key, email text unique not null);
    create function auth.uid() returns uuid language sql stable as $$
      select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
    $$;
    grant usage on schema public, auth to anon, authenticated;
    grant execute on function auth.uid() to anon, authenticated;
  `);
  await db.query('insert into auth.users (id,email) values ($1,$2),($3,$4)',
    [alice, 'alice@example.invalid', bob, 'bob@example.invalid']);
  const migration = await readFile(new URL('../migrations/20261001000000_create_ledgy_backend.sql', import.meta.url), 'utf8');
  await db.exec(migration);
  checks++; // Applying the migration validates the actual PostgreSQL syntax/DDL.
  await db.exec(await readFile(new URL('../migrations/20261002000000_sync_window.sql', import.meta.url), 'utf8'));
  checks++;
  equal((await db.query("select prosecdef from pg_proc where oid='public.ledgy_sync_window()'::regprocedure")).rows[0].prosecdef,
    false, 'sync window runs with caller privileges, not a privileged definer');
  await db.exec('set role anon');
  await denied('select public.ledgy_sync_window()', [], '42501', 'anon cannot read sync metadata');
  await authenticate(alice);
  const emptyWindow = (await db.query('select public.ledgy_sync_window() as window')).rows[0].window;
  equal(emptyWindow.has_data, false, 'empty user starts without remote data');
  equal(Number.isFinite(Date.parse(emptyWindow.server_time)), true, 'window returns a usable server timestamp');
  equal((await db.query("select (public.ledgy_sync_window()->>'server_time')::timestamptz between now() - interval '1 second' and clock_timestamp() as matches")).rows[0].matches,
    true, 'window timestamp comes from the PostgreSQL server clock');

  for (const table of tables) {
    const metadata = (await db.query(
      "select relrowsecurity from pg_class where oid = ('public.' || $1)::regclass", [table])).rows[0];
    equal(metadata.relrowsecurity, true, table + ' has RLS enabled');
    const policies = (await db.query(
      'select cmd, roles::text as roles, qual, with_check from pg_policies where schemaname=$1 and tablename=$2 order by cmd',
      ['public', table])).rows;
    equal(policies.map(p => p.cmd), ['DELETE', 'INSERT', 'SELECT', 'UPDATE'], table + ' has four policies');
    equal(policies.every(p => p.roles === '{authenticated}'), true, table + ' policies require login');
    const update = policies.find(p => p.cmd === 'UPDATE');
    equal(Boolean(update.qual && update.with_check), true, table + ' UPDATE checks both owner versions');
    const indexes = (await db.query(
      'select indexdef from pg_indexes where schemaname=$1 and tablename=$2', ['public', table])).rows;
    equal(indexes.some(i => /\(user_id, updated_at\)/.test(i.indexdef)), true, table + ' has sync index');
    for (const role of ['anon', 'authenticated']) {
      const privilege = (await db.query(
        "select has_table_privilege($1, 'public.' || $2, 'TRUNCATE') as allowed", [role, table])).rows[0];
      equal(privilege.allowed, false, role + ' cannot truncate ' + table);
    }
    const type = (await db.query(
      'select data_type from information_schema.columns where table_schema=$1 and table_name=$2 and column_name=$3',
      ['public', table, table === 'accounts' ? 'initial_balance' : table === 'categories' ? 'updated_at' : 'amount'])).rows[0];
    equal(type.data_type, table === 'categories' ? 'timestamp with time zone' : 'bigint', table + ' preserves types');
  }

  for (const owner of [alice, bob]) {
    fixtures[owner] = {};
    await authenticate(owner);
    for (const table of tables) {
      const row = await create(table, owner);
      fixtures[owner][table] = row;
      equal(row.user_id, owner, table + ' user_id defaults to auth.uid()');
      equal(row.server_clock_matches, true, table + ' insert overwrites device timestamp');
      equal(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(row.id), true, table + ' generates UUID v4');
    }
    equal((await db.query('select public.ledgy_sync_window() as window')).rows[0].window.has_data,
      true, 'sync window sees the logged-in owner data');
    if (owner === alice) {
      await authenticate(bob);
      equal((await db.query('select public.ledgy_sync_window() as window')).rows[0].window.has_data,
        false, 'other user data does not affect bootstrap metadata');
    }
  }

  for (const table of tables) {
    const a = fixtures[alice][table];
    const b = fixtures[bob][table];
    await authenticate(alice);
    equal((await db.query('select id from public.' + table + ' where id=$1', [a.id])).rows.length, 1,
      table + ' owner can select');
    const updated = await db.query('update public.' + table +
      " set updated_at='2000-01-01T00:00:00Z', is_dirty=false where id=$1 returning updated_at=now() as server_clock_matches", [a.id]);
    equal(updated.rows[0].server_clock_matches, true, table + ' update overwrites device timestamp');
    await denied('update public.' + table + ' set user_id=$1 where id=$2', [bob, a.id], '42501',
      table + ' owner cannot reassign ownership');
    equal((await db.query('update public.' + table + ' set is_dirty=false where id=$1 returning id', [b.id])).rows.length, 0,
      table + ' cannot update another user');
    equal((await db.query('delete from public.' + table + ' where id=$1 returning id', [b.id])).rows.length, 0,
      table + ' cannot delete another user');
    equal((await db.query('select id from public.' + table + ' where id=$1', [b.id])).rows.length, 0,
      table + ' cannot read another user');
    await denied(...insert(table, { ...fields(table, alice), user_id: bob }), '42501',
      table + ' cannot insert with forged owner');

    const upsert = await db.query(...insert(table, { ...fields(table, alice), id: a.id, updated_at: '2099-01-01T00:00:00Z' }, true));
    equal(upsert.rows[0].server_clock_matches, true, table + ' upsert uses server timestamp');
    await db.query('update public.' + table + " set deleted_at=now(),updated_at='2099-01-01T00:00:00Z' where id=$1", [a.id]);
    const tombstone = (await db.query('select deleted_at from public.' + table + ' where id=$1', [a.id])).rows;
    equal(tombstone.length === 1 && tombstone[0].deleted_at != null, true, table + ' owner can pull tombstones');
    equal((await db.query('select id from public.' + table + ' where id=$1 and deleted_at is null', [a.id])).rows.length, 0,
      table + ' UI filter excludes tombstones');
    const temporary = await create(table, alice);
    equal((await db.query('delete from public.' + table + ' where id=$1 returning id', [temporary.id])).rows.length, 1,
      table + ' owner can delete');

    await db.exec('reset role; set role anon');
    await denied('select * from public.' + table, [], '42501', table + ' denies anon');
    await authenticate(bob);
    equal((await db.query('select id from public.' + table + ' where id=$1', [b.id])).rows.length, 1,
      table + ' second user can access their own rows');
  }

  await authenticate(alice);
  for (const table of ['transactions', 'recurring_rules']) {
    await denied(...insert(table, { ...fields(table, alice), account_id: fixtures[bob].accounts.id }), '23503',
      table + ' refuses another user source asset');
    await denied(...insert(table, { ...fields(table, alice), type: 'transfer', to_account_id: fixtures[bob].accounts.id }), '23503',
      table + ' refuses another user target asset');
    await denied(...insert(table, { ...fields(table, alice), type: 'transfer', to_account_id: fixtures[alice].accounts.id }), '23514',
      table + ' refuses self-transfer');
    await denied(...insert(table, { ...fields(table, alice), type: 'transfer' }), '23514',
      table + ' requires transfer destination');
  }
  for (const table of ['transactions', 'budgets', 'recurring_rules']) {
    await denied(...insert(table, { ...fields(table, alice), category_id: fixtures[bob].categories.id }), '23503',
      table + ' refuses another user category');
    await denied(...insert(table, { ...fields(table, alice), amount: -1 }), '23514',
      table + ' refuses negative amount');
  }
  await denied(...insert('categories', { name: 'Invalid', kind: 'other' }), '23514', 'category kind is validated');
  await denied(...insert('recurring_rules', { ...fields('recurring_rules', alice), interval: 0 }), '23514', 'recurrence interval is positive');
  await denied(...insert('recurring_rules', { ...fields('recurring_rules', alice), frequency: 'hourly' }), '23514', 'recurrence frequency is validated');
  await denied(...insert('transactions', { ...fields('transactions', alice), type: 'other' }), '23514', 'transaction type is validated');

  const target = await create('accounts', alice);
  const transfer = await create('transactions', alice, { type: 'transfer', to_account_id: target.id, category_id: null });
  equal(transfer.to_account_id, target.id, 'valid own-asset transfer works');
  const nullableCategory = await create('transactions', alice, { category_id: null });
  equal(nullableCategory.category_id, null, 'nullable categories match the local schema');
  const balance = (await db.query('select initial_balance::text as balance from public.accounts where id=$1',
    [fixtures[alice].accounts.id])).rows[0];
  equal(balance.balance, '3000000000', 'money does not overflow a 32-bit integer');
  await denied('delete from public.accounts where id=$1', [fixtures[alice].accounts.id], '23503', 'hard delete preserves referenced history');

  // Exercise the account RPC on isolated users, never a hosted account.
  await db.exec('reset role');
  await db.exec(await readFile(new URL('../migrations/20261007000000_transfer_recipients.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../migrations/20261007010000_account_profile.sql', import.meta.url), 'utf8'));
  checks += 2;
  equal((await db.query("select proconfig from pg_proc where oid='public.ledgy_delete_account()'::regprocedure")).rows[0].proconfig,
    ['search_path=""'], 'account RPC uses an empty search path');
  await db.exec('set role anon');
  await denied('select public.ledgy_delete_account()', [], '42501', 'anonymous users cannot delete accounts');
  await authenticate(null);
  await denied('select public.ledgy_delete_account()', [], '42501', 'missing user claims cannot delete accounts');
  await authenticate(alice);
  await db.query('select public.ledgy_delete_account()');
  await db.exec('reset role');
  equal((await db.query('select id from auth.users where id=$1', [alice])).rows.length, 0,
    'account RPC removes the caller');
  equal((await db.query('select id from auth.users where id=$1', [bob])).rows.length, 1,
    'account RPC retains other accounts');
  for (const table of tables) {
    equal((await db.query('select count(*)::integer as count from public.' + table + ' where user_id=$1',
      [alice])).rows[0].count, 0, table + ' follows Auth user deletion');
    equal((await db.query('select count(*)::integer as count from public.' + table + ' where user_id=$1',
      [bob])).rows[0].count, 1, table + ' retains the other user ledger');
  }
  console.log('PASS: ' + checks + ' PostgreSQL schema/security checks (isolated PGlite, no hosted database).');
} finally {
  await db.close();
}
