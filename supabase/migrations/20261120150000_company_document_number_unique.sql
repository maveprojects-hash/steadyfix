-- Protect company-local quote and invoice numbers against concurrent creation.
-- Existing duplicates must be reviewed before this index is applied.
do $$
begin
  if exists (
    select company_id, kind, number
    from public.documents
    where kind in ('quote', 'invoice')
      and number is not null
    group by company_id, kind, number
    having count(*) > 1
  ) then
    raise exception 'Duplicate quote or invoice numbers exist within a company. Review them before applying this migration.';
  end if;
end $$;

create unique index if not exists documents_company_kind_number_uidx
  on public.documents (company_id, kind, number)
  where kind in ('quote', 'invoice') and number is not null;
