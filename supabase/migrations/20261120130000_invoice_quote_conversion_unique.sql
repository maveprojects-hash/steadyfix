-- Prevent concurrent quote conversion from creating multiple invoices for the same quote.
-- Fail closed if legacy duplicate conversions already exist; those must be reviewed before applying.
do $$
begin
  if exists (
    select company_id, converted_from
    from public.documents
    where kind = 'invoice'
      and converted_from is not null
    group by company_id, converted_from
    having count(*) > 1
  ) then
    raise exception 'Duplicate quote conversions exist. Review and resolve them before applying this migration.';
  end if;
end $$;

create unique index if not exists documents_invoice_converted_from_company_uidx
  on public.documents (company_id, converted_from)
  where kind = 'invoice' and converted_from is not null;
