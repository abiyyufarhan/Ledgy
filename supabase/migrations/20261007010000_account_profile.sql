-- Called only after the user confirms account deletion in the profile page.
-- The caller can delete only their own Auth account. Existing user_id foreign
-- keys cascade deletion to that user's ledger; no service key enters the app.
begin;

create function public.ledgy_delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  delete from auth.users where id = caller;
end;
$$;

revoke all on function public.ledgy_delete_account() from public, anon;
grant execute on function public.ledgy_delete_account() to authenticated;
notify pgrst, 'reload schema';
commit;
