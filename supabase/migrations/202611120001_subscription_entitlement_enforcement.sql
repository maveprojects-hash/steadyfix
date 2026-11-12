-- Enforce subscription entitlement in the database as well as the browser.
-- Active subscriptions and unexpired trial/pending-trial accounts retain access.
-- Internal owner account remains exempt. Expired/cancelled/past-due accounts are denied
-- access to tenant business data while retaining profile, company and support access.

CREATE OR REPLACE FUNCTION public.company_subscription_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.companies c ON c.id = p.company_id
    WHERE p.id = auth.uid()
      AND p.active IS TRUE
      AND (
        c.plan = 'internal'
        OR c.subscription_status = 'active'
        OR (
          c.subscription_status IN ('trialing', 'pending')
          AND c.trial_ends_at IS NOT NULL
          AND c.trial_ends_at > now()
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.company_subscription_is_current(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.companies c
    WHERE c.id = p_company_id
      AND (
        c.plan = 'internal'
        OR c.subscription_status = 'active'
        OR (
          c.subscription_status IN ('trialing', 'pending')
          AND c.trial_ends_at IS NOT NULL
          AND c.trial_ends_at > now()
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION public.company_subscription_access() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_subscription_access() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.company_subscription_is_current(uuid) FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'company_id'
      AND a.attnum > 0 AND NOT a.attisdropped
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity
      AND c.relname NOT IN ('companies', 'profiles', 'sites', 'company_settings', 'support_tickets')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS subscription_entitlement_gate ON public.%I', t.relname);
    EXECUTE format(
      'CREATE POLICY subscription_entitlement_gate ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (public.company_subscription_access()) WITH CHECK (public.company_subscription_access())',
      t.relname
    );
  END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.add_site(p_name text, p_address text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  cid uuid := auth_company();
  sid uuid;
  lim int;
BEGIN
  IF auth.uid() IS NULL OR auth_role() NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only signed-in owners and managers can add sites';
  END IF;
  IF NOT public.company_subscription_is_current(cid) THEN
    RAISE EXCEPTION 'Your trial or subscription has ended. Please choose a plan to continue.';
  END IF;
  SELECT max_sites INTO lim FROM companies WHERE id = cid;
  IF (SELECT count(*) FROM sites WHERE company_id = cid AND active) >= lim THEN
    RAISE EXCEPTION 'Site limit reached for your plan (% sites). Upgrade to add more.', lim;
  END IF;
  INSERT INTO sites (company_id, name, address)
  VALUES (cid, p_name, p_address)
  RETURNING id INTO sid;
  RETURN sid;
END
$$;

CREATE OR REPLACE FUNCTION public.accept_invite(p_token text, p_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  uid uuid := auth.uid();
  inv invitations;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id = uid) THEN RAISE EXCEPTION 'Account already set up'; END IF;
  SELECT * INTO inv FROM invitations
    WHERE token = p_token AND NOT accepted AND expires_at > now()
      AND lower(email) = lower(auth.jwt() ->> 'email');
  IF NOT FOUND THEN RAISE EXCEPTION 'Invite is invalid, expired or for a different email'; END IF;
  IF NOT public.company_subscription_is_current(inv.company_id) THEN
    RAISE EXCEPTION 'This company subscription is not active. Contact the company owner.';
  END IF;
  INSERT INTO profiles (id, company_id, full_name, role)
    VALUES (uid, inv.company_id, p_name, inv.role);
  INSERT INTO user_sites (user_id, site_id, company_id)
    SELECT uid, s.id, s.company_id FROM sites s
    WHERE s.id = ANY(inv.site_ids) AND s.company_id = inv.company_id;
  UPDATE invitations SET accepted = true WHERE id = inv.id;
  RETURN inv.company_id;
END
$$;

CREATE OR REPLACE FUNCTION public.record_subscription(p_sub text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth_role() NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;
  IF p_sub IS NULL OR length(trim(p_sub)) < 5 OR length(trim(p_sub)) > 128 THEN
    RAISE EXCEPTION 'Invalid PayPal subscription reference';
  END IF;
  UPDATE companies
  SET paypal_subscription_id = trim(p_sub),
      subscription_status = CASE WHEN subscription_status = 'active' THEN 'active' ELSE 'pending' END
  WHERE id = auth_company();
END
$$;

CREATE OR REPLACE FUNCTION public.agent_sync(p_agent_key text, p_devices jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  st sites;
  co companies;
  d jsonb;
  s sensors;
  ext text;
  seen text[] := '{}';
  created int := 0;
  skipped int := 0;
  cnt int;
BEGIN
  SELECT * INTO st FROM sites WHERE agent_key = p_agent_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown gateway key'; END IF;
  SELECT * INTO co FROM companies WHERE id = st.company_id;
  IF NOT FOUND OR NOT public.company_subscription_is_current(co.id) THEN
    RAISE EXCEPTION 'Your trial or subscription has ended. Please choose a plan to continue.';
  END IF;
  IF NOT coalesce(co.gateway_access, false) THEN
    RAISE EXCEPTION 'Your plan does not include the computer gateway software. Upgrade to the PRO plan.';
  END IF;
  FOR d IN SELECT value FROM jsonb_array_elements(p_devices) LOOP
    ext := coalesce(nullif(d->>'mac', ''), d->>'ip');
    CONTINUE WHEN ext IS NULL;
    seen := seen || ext;
    SELECT * INTO s FROM sensors WHERE site_id = st.id AND external_id = ext;
    IF NOT FOUND THEN
      SELECT count(*) INTO cnt FROM sensors WHERE company_id = st.company_id;
      IF co.max_devices IS NOT NULL AND cnt >= co.max_devices THEN
        skipped := skipped + 1;
        CONTINUE;
      END IF;
      INSERT INTO sensors (company_id, site_id, name, kind, unit, external_id)
      VALUES (st.company_id, st.id, coalesce(nullif(d->>'name', ''), d->>'ip'), 'network_device', '1 = up', ext)
      RETURNING * INTO s;
      created := created + 1;
    END IF;
    INSERT INTO readings (company_id, sensor_id, value)
    VALUES (st.company_id, s.id, CASE WHEN coalesce((d->>'up')::boolean, false) THEN 1 ELSE 0 END);
  END LOOP;
  INSERT INTO readings (company_id, sensor_id, value)
    SELECT company_id, id, 0 FROM sensors
    WHERE site_id = st.id AND kind = 'network_device' AND external_id IS NOT NULL
      AND NOT (external_id = ANY(seen));
  IF random() < 0.02 THEN
    DELETE FROM readings WHERE company_id = st.company_id AND read_at < now() - interval '60 days';
  END IF;
  RETURN jsonb_build_object('ok', true, 'created', created, 'skipped', skipped, 'latest_version', '2.0');
END
$$;

CREATE OR REPLACE FUNCTION public.ingest_position(
  p_key text, p_lat double precision, p_lng double precision,
  p_speed numeric DEFAULT 0, p_heading numeric DEFAULT NULL,
  p_odometer numeric DEFAULT NULL, p_at timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v vehicles%rowtype;
  t timestamptz;
BEGIN
  SELECT * INTO v FROM vehicles WHERE device_key = p_key LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown tracker key'; END IF;
  IF NOT public.company_subscription_is_current(v.company_id) THEN
    RAISE EXCEPTION 'Your trial or subscription has ended. Please choose a plan to continue.';
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL OR abs(p_lat) > 90 OR abs(p_lng) > 180 THEN
    RAISE EXCEPTION 'Bad position';
  END IF;
  t := least(coalesce(p_at, now()), now());
  INSERT INTO vehicle_positions (company_id, vehicle_id, recorded_at, lat, lng, speed_kmh, heading)
    VALUES (v.company_id, v.id, t, p_lat, p_lng, coalesce(p_speed, 0), p_heading);
  UPDATE vehicles SET last_lat = p_lat, last_lng = p_lng, last_speed = coalesce(p_speed, 0),
    last_seen = t, odometer_km = coalesce(p_odometer, odometer_km) WHERE id = v.id;
  RETURN jsonb_build_object('ok', true);
END
$$;

CREATE OR REPLACE FUNCTION public.ingest_reading(p_key text, p_value numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  s sensors;
BEGIN
  SELECT * INTO s FROM sensors WHERE device_key = p_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown device key'; END IF;
  IF NOT public.company_subscription_is_current(s.company_id) THEN
    RAISE EXCEPTION 'Your trial or subscription has ended. Please choose a plan to continue.';
  END IF;
  INSERT INTO readings (company_id, sensor_id, value) VALUES (s.company_id, s.id, p_value);
  RETURN jsonb_build_object(
    'ok', true,
    'alert', (s.alert_min IS NOT NULL AND p_value < s.alert_min)
      OR (s.alert_max IS NOT NULL AND p_value > s.alert_max)
  );
END
$$;

-- These RPCs require a signed-in account. Hardware/gateway ingestion RPCs above
-- intentionally remain callable with a device key and enforce subscription status internally.
REVOKE ALL ON FUNCTION public.signup_company(text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.signup_company(text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.accept_invite(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_invite(text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.add_site(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_site(text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.record_subscription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_subscription(text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_activity() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activity() TO authenticated;
REVOKE ALL ON FUNCTION public.support_inbox() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_inbox() TO authenticated;
REVOKE ALL ON FUNCTION public.support_reply(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_reply(uuid,text,text) TO authenticated;

-- Trigger functions are not application RPC endpoints.
REVOKE ALL ON FUNCTION public.apply_plan_limits() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_device_limit() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.protect_internal() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.protect_internal()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO public
AS $$
BEGIN
  IF OLD.plan = 'internal' THEN
    NEW.plan := 'internal';
    NEW.subscription_status := 'active';
    NEW.max_devices := NULL;
    NEW.max_sites := 999;
    NEW.gateway_access := true;
  END IF;
  RETURN NEW;
END
$$;
