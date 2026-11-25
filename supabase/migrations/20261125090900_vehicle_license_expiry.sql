-- Add the vehicle licence expiry field already used by fleet forms and dashboard alerts.
alter table public.vehicles add column if not exists license_expiry date;
