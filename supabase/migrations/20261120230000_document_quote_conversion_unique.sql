-- Prevent duplicate invoice conversions of the same quote at database level.
begin;
do $$
begin
  if exists (
    select 1 from public.documents
    where kind='invoice' and converted_from is not null
    group by company_id,converted_from
    having count(*)>1
  ) then
    raise exception 'Duplicate quote conversions already exist; reconcile them before applying the unique conversion index';
  end if;
end $$;
create unique index if not exists documents_one_invoice_per_quote_idx
  on public.documents(company_id,converted_from)
  where kind='invoice' and converted_from is not null;
commit;
