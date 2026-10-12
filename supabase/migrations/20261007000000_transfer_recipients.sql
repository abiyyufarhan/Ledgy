-- Preserve existing transfers between assets and support external recipients.
begin;

alter table public.transactions
  add column recipient_name text,
  add column recipient_account text;

alter table public.transactions
  drop constraint transactions_transfer_check,
  add constraint transactions_transfer_check check (
    (type = 'transfer' and (
      (to_account_id is not null and account_id <> to_account_id
        and recipient_name is null and recipient_account is null)
      or
      (to_account_id is null
        and recipient_name is not null and length(btrim(recipient_name)) > 0
        and recipient_account is not null and length(btrim(recipient_account)) > 0)
    ))
    or
    (type <> 'transfer' and to_account_id is null
      and recipient_name is null and recipient_account is null)
  );

notify pgrst, 'reload schema';
commit;
