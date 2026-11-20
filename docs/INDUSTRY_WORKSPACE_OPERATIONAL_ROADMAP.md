# Industry Workspace Operational Completion Roadmap

## Purpose and production guardrails
Industry presets must be operational workflows, not only menu labels or configuration descriptions. Implement against isolated feature branches and PRs. Do not merge or deploy without explicit release approval. Preserve existing company/site authorization, tenant isolation, and current live behavior.

## Baseline observations
- Industry workspace selection and company-industry profile are present.
- Logistics workspace contains waybill/consignment, tracking scan, and proof-of-delivery UI entry points on the logistics-digital-pod branch.
- Fleet foundations exist (vehicle records, workshop/job cards, checklist/tracking views), but static markers and menu presence do not prove all operational workflows, live GPS ingestion, or provider integrations work.
- Remaining work must be verified by behavior, data persistence, company/site scope, and tests.

## Completion standard for every industry
A workspace is complete only when all applicable items are implemented and tested:
1. Industry-specific dashboard, navigation, and terminology.
2. CRUD flows for core records with validation and company/site scoping.
3. Operational lifecycle and status transitions, with audit trail.
4. Work orders/job cards linked to originating asset, customer, contract, or event.
5. Staff/technician assignment, schedule, and notifications.
6. Inventory/materials/consumables integration where applicable.
7. Quotes, invoices, and customer approvals where applicable.
8. Reports/KPIs and export/print output.
9. Permissions and tenant/site isolation tests.
10. Empty, loading, error, and offline/unsupported-provider states; no fake controls or success claims.

## Logistics & transport acceptance
- Create/update consignment; unique tracking number; sender, recipient, address, service, package details, handling notes.
- Waybill view and print/export layouts (A4 and parcel-label formats), company branding, template configuration.
- Manifest creation and dispatch/loading events.
- Scan lifecycle: created, collected, in transit, out for delivery, delivered, failed, returned; scans store timestamp, actor, location, notes.
- Proof of delivery: recipient/signature, photo, delivery time, location; failed delivery reason and reattempt.
- Driver/vehicle assignment and ETA; GPS-linked location, last-seen freshness, route deviations, arrival/departure, geofence/exception alerts.
- Customer-facing tracking view with access restrictions.
- Consignment-to-order/job/invoice integration and regression tests.

## Fleet acceptance
- Pre/post-trip inspections, driver, vehicle, odometer, photos, defects and reviewer.
- Defect-to-work-order conversion retaining source inspection link.
- Fuel capture (volume, price, odometer, supplier, receipt) and cost/efficiency reports.
- Tyre positions, tread, replacement/rotation history.
- Compliance document expiries and alerts.
- Live GPS ingestion/provider setup, map, route history, stale/offline signal, speed, geofence, idle, incidents/SOS where provider supports it.
- Downtime, utilisation, availability and costs; tenant/site RLS and regression tests.

## Managed print / copier & office automation acceptance
- Customer device fleet, serials, locations, meters and meter-read history.
- Contracts, SLA, cost-per-page/rates, monthly billing calculations and invoice reconciliation.
- Toner/consumables forecasting and stock allocation; device telemetry and alert freshness.
- Fault intake, service dispatch, technician assignment, parts, labour, service history.
- Installations, moves, swaps, warranties, preventative maintenance, customer approvals.
- Customer fleet report, SLA breach and billing tests.

## Workshop and specialist service acceptance
- Bookings, inspections, diagnostics, work cards, technician/time, parts, approval, road test, warranty, invoice.
- Specialist presets for HVAC/refrigeration, electrical, plumbing, security systems, cleaning, agriculture, manufacturing, plant hire, and property/facilities should enable relevant modules and configure workflows—not merely change labels.
- Industry-specific compliance, asset attributes, preventive schedules, materials, service reports and lifecycle statuses are required.

## iAssistant customization contract
- Apply validated company/site settings to an existing industry profile: service catalog, custom fields, workflow stages, roles, approvals, schedules, alerts, KPI definitions and optional modules.
- Never generate arbitrary executable code, bypass permission checks, alter tenant boundaries, or silently overwrite saved settings.
- Preview changes, validate schema/allowed values, show a diff, require owner/manager confirmation, record audit metadata, and provide rollback.

## Suggested implementation sequence
1. Logistics operational lifecycle and label/waybill/POD tests.
2. Fleet inspections, defect work orders, fuel/tyre/compliance data and GPS provider integration tests.
3. Managed print/copier contracts, meters, consumables, SLA and billing workflows.
4. Automotive workshop and plant-hire workflows.
5. HVAC, electrical, plumbing and security specialist templates.
6. Manufacturing, agriculture, cleaning/hygiene, hospitality and property/facilities workflow gaps.
7. iAssistant configuration validation, preview/diff, audit, rollback and end-to-end tests.

## Release checklist
- No production changes from this branch.
- PR review required before merge.
- Tests cover persistence, lifecycle transitions, company/site authorization, cross-tenant denial, errors, and regression for existing industry presets.
- Provider-dependent features are clearly marked unavailable until provider credentials/configuration and live integration tests are present.
