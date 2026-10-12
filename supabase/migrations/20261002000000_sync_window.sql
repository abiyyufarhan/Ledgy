-- Apply after phase 5. Supplies a server clock and bootstrap metadata without
-- depending on a device clock. All reads retain the caller's owner-only RLS.
begin;
create function public.ledgy_sync_window()
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'server_time', pg_catalog.clock_timestamp(),
    'has_data',
      exists(select 1 from public.accounts where user_id = (select auth.uid()))
      or exists(select 1 from public.categories where user_id = (select auth.uid()))
      or exists(select 1 from public.transactions where user_id = (select auth.uid()))
      or exists(select 1 from public.budgets where user_id = (select auth.uid()))
      or exists(select 1 from public.recurring_rules where user_id = (select auth.uid()))
  );
$function$;
revoke all on function public.ledgy_sync_window() from public, anon;
grant execute on function public.ledgy_sync_window() to authenticated;
commit;
