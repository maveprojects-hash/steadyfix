-- Quote conversion is a single database transaction and an idempotent RPC.
-- Row-locking serializes conversion attempts; the partial unique index is the final guard.
create or replace function public.convert_quote_to_invoice(
  p_quote_id uuid,
  p_invoice_number text
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_company uuid := public.auth_company();
  v_user uuid := auth.uid();
  v_role text := public.auth_role();
  v_quote public.documents%rowtype;
  v_invoice public.documents%rowtype;
  v_existing boolean := false;
begin
  if v_user is null or v_company is null then
    raise exception 'Authentication required';
  end if;
  if v_role not in ('owner','manager') then
    raise exception 'Only owners and managers can convert quotes';
  end if;
  if p_invoice_number is null or length(btrim(p_invoice_number)) = 0 then
    raise exception 'Invoice number is required';
  end if;

  select d.* into v_quote
  from public.documents d
  where d.id = p_quote_id and d.company_id = v_company and d.kind = 'quote'
  for update;

  if not found then
    raise exception 'Quote unavailable or outside your company';
  end if;
  if not public.auth_site_ok(v_quote.site_id) then
    raise exception 'You do not have access to this quote site';
  end if;
  if v_quote.status = 'cancelled' then
    raise exception 'Cancelled quotes cannot be converted';
  end if;

  select d.* into v_invoice
  from public.documents d
  where d.company_id = v_company and d.kind = 'invoice' and d.converted_from = v_quote.id
  limit 1;
  if found then
    v_existing := true;
  else
    insert into public.documents (
      company_id, site_id, kind, number, customer_id, customer_name,
      issue_date, due_date, status, currency, vat_rate, lines, notes,
      subtotal, vat_amount, total, converted_from, reference, sales_rep,
      discount_pct, discount_amount, paid_amount
    )
    values (
      v_company, v_quote.site_id, 'invoice', btrim(p_invoice_number),
      v_quote.customer_id, v_quote.customer_name, current_date, current_date + 30,
      'draft', v_quote.currency, v_quote.vat_rate, v_quote.lines, v_quote.notes,
      v_quote.subtotal, v_quote.vat_amount, v_quote.total, v_quote.id,
      v_quote.reference, v_quote.sales_rep, coalesce(v_quote.discount_pct,0),
      coalesce(v_quote.discount_amount,0), 0
    )
    on conflict (company_id, converted_from)
      where kind = 'invoice' and converted_from is not null
    do nothing
    returning * into v_invoice;

    if not found then
      select d.* into v_invoice
      from public.documents d
      where d.company_id = v_company and d.kind = 'invoice' and d.converted_from = v_quote.id
      limit 1;
      if not found then
        raise exception 'Invoice conversion failed. Please retry.';
      end if;
      v_existing := true;
    end if;
  end if;

  update public.documents
  set status = 'accepted'
  where id = v_quote.id and company_id = v_company and kind = 'quote';

  if not found then
    raise exception 'Quote state could not be updated; conversion rolled back';
  end if;

  return jsonb_build_object('invoice_id', v_invoice.id, 'already_converted', v_existing);
end;
$$;

revoke all on function public.convert_quote_to_invoice(uuid,text) from public, anon;
grant execute on function public.convert_quote_to_invoice(uuid,text) to authenticated;
