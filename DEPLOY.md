# Deploying ProOS

ProOS is a Next.js 15 application with a PostgreSQL database and one background worker. Everything below was exercised
on the production build; the Docker images were written to the standard Next.js standalone layout but have not been
built on this machine (no Docker here), so run the first `docker compose up` on the target host and watch the logs.

## 1. Option A — Docker Compose on a VPS (recommended: Indian region for DPDP data localisation)

```bash
cp .env.production.example .env.production      # fill in secrets (see §3)
export POSTGRES_PASSWORD='a-long-random-password'
docker compose up -d --build                     # db → migrate (schema push) → web + worker
docker compose logs -f web worker
```

* Web on port 3100; put Caddy / nginx in front with TLS and pass `X-Forwarded-For` (the rate limiter keys on it).
* First admin: open `/signup` to create the firm workspace (starts a 60-day trial). Demo data is only seeded when
  `SEED_DEMO=1` is set on the `migrate` service.
* Row-level security (optional, defence in depth): `psql $DATABASE_URL -f prisma/sql/rls.sql` and run the app with a
  role that lacks BYPASSRLS; the policies read `current_setting('app.firm_id')`, which you set per connection in a
  Prisma `$extends` middleware when you adopt RLS. Application-level firm scoping is already enforced on every query.

## 2. Option B — Managed host (Vercel / Railway / Render) + managed Postgres

1. `npm run db:push:pg` against the managed database (generates the Postgres schema and pushes it).
2. Build command: `node scripts/make-postgres-schema.js && npx prisma generate --schema prisma/schema.postgres.prisma && next build`.
3. Run the worker as a separate always-on service: `npm run worker`. If the host has no long-running processes,
   schedule `GET /api/cron/dispatch?secret=$CRON_SECRET` every minute and `GET /api/cron/daily?secret=$CRON_SECRET`
   daily at 08:00 IST from the platform's cron instead.
4. Set the environment variables from `.env.production.example`.

## 3. Integrations and what each secret unlocks

| Secret | Without it | With it |
| --- | --- | --- |
| `SUREPASS_API_TOKEN` | deterministic mock KYB data | live PAN, PAN→GSTIN, MCA master data, ICAI member checks |
| `RAZORPAY_KEY_ID/SECRET` + `RAZORPAY_WEBHOOK_SECRET` | mock payment links; plans activate immediately | real payment links; invoices and plans mark paid on `payment_link.paid` webhook → `/api/webhooks/razorpay` |
| `WHATSAPP_TOKEN` + `WHATSAPP_PHONE_ID` + `WHATSAPP_APP_SECRET` + `WHATSAPP_VERIFY_TOKEN` | messages stay queued in the outbox (visible at `/outbox`) | delivery via Meta Cloud API; statuses and inbound messages via `/api/webhooks/whatsapp`. Create templates `proos_update`, `proos_due_reminder`, `proos_payment_reminder` (Utility) and `proos_marketing` (Marketing) in WhatsApp Manager, each with one `{{1}}` body variable |
| `SMTP_*` | email queued only | SMTP delivery |
| `IMAP_*` | inbound email not ingested | firm mailbox polled every 2 minutes by the worker into the shared inbox |
| `UPLOAD_DIR` | `./data/uploads` (compose mounts a volume) | any path; replace `src/lib/documents/storage.ts` for S3 |
| `CRON_SECRET` | cron endpoints refuse | `/api/cron/*` callable by schedulers |

### 3a. What was verified against provider documentation (Nov 2026)

* **Razorpay Payment Links** — request/response fields match the adapter; `reference_id` must be unique and ≤ 40 characters, which `razorpayReference()` now enforces (slashes in invoice numbers are replaced).
* **Meta WhatsApp webhooks** — inbound (`entry[].changes[].value.messages[]`) and status (`value.statuses[]`) shapes match the webhook handler exactly.
* **emSigner / emBridge** — no public protocol; ports seen across releases (1585, 1645, 2095, 2568, 2868, 4587, 8080) are all probed. The command vocabulary still needs one captured exchange from a real token.
* **Surepass** — the API reference on apidog is password-protected. The adapter uses the catalogue product names as paths (`/pan/pan-comprehensive`, `/corporate/gstin-by-pan`, `/corporate/company-details`), reads response fields tolerantly, and every path is overridable with `SUREPASS_PATH_*`. Confirm with `npm run surepass:contract -- <PAN> <CIN>` once a token is in `.env`.

## 4. Chrome extension

Load `extension/` unpacked (or package it for the Chrome Web Store), set the server URL and an API key from
`/settings` in the popup. Notice sync runs every 30 minutes over logged-in portal tabs.

## 5. Hardware DSC signing

Partners install eMudhra emSigner / emBridge on their PCs; the signing desk probes `wss://127.0.0.1:1585` (then 1645,
8080, and `ws://`) and lists token certificates. The command vocabulary lives in `BRIDGE_COMMANDS` in
`src/components/dsc-signer.tsx`; adjust after capturing one real exchange from the installed agent. Simulated
signatures are refused in production.

## 6. Operations

* Health: `GET /api/health` (used by the Docker HEALTHCHECK).
* Backups: `pg_dump` nightly plus the `uploads` volume (client documents); the zero-knowledge vault stores only ciphertext, so backups never contain client portal
  passwords. The vault passphrase lives only with the firm.
* Data export: `/settings/export` returns the firm's complete data as JSON (also during the 30-day post-plan window).
* Rate limits are per web instance (in-memory). Behind more than one instance, limit at the proxy or add Redis.
* Upgrades: `docker compose build && docker compose up -d` — the `migrate` service pushes schema changes before web starts.

## 7. Production checklist

- [ ] TLS terminated at the proxy; `APP_URL` set to the public origin (used in links sent to clients)
- [ ] All `*_SECRET` / verify tokens are long random values
- [ ] WhatsApp templates approved; webhook subscribed to `messages` and `message_template_status_update`
- [ ] Razorpay webhook pointed at `/api/webhooks/razorpay` with the same secret
- [ ] `SEED_DEMO` unset; demo firm absent
- [ ] Threshold table reviewed against current notifications (`src/lib/engine/thresholds.ts`), in particular the small-company limit
- [ ] AQMM level thresholds in `src/lib/aqmm/rubric.ts` aligned to the ICAI Implementation Guide
