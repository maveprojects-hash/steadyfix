-- Reduce the anonymous API surface. Customer data is accessed only after sign-in.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon;

REVOKE ALL ON FUNCTION public.auth_company() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auth_company() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.auth_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auth_role() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.auth_site_ok(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auth_site_ok(uuid) TO authenticated, service_role;

-- Device-key endpoints remain callable without a user login; each validates its
-- per-device/site key and rejects expired or non-entitled companies internally.
GRANT EXECUTE ON FUNCTION public.agent_sync(text,jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ingest_position(text,double precision,double precision,numeric,numeric,numeric,timestamptz) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ingest_reading(text,numeric) TO anon, authenticated, service_role;

REVOKE ALL ON TABLE public.plans FROM anon;
GRANT SELECT ON TABLE public.plans TO authenticated, service_role;
