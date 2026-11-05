# ProOS — Practice Operating System for Indian CA / CS / CMA firms

Stage 1 build of the platform described in the research synthesis and master execution plan
(AQMM v2.0 readiness, GST IMS automation, multi-disciplinary compliance, WhatsApp/email client communication).

## Status: all four stages built — ready to deploy (see DEPLOY.md)

| Module | Where | What it does |
| --- | --- | --- |
| Auth, roles, plans | `src/lib/auth/`, `src/lib/plans.ts`, `/signup`, `/settings/users`, `/settings/billing` | scrypt + cookie sessions, role permissions (maker / checker / EQCR / partner), 60-day trial, flat tiers with free articled seats, Razorpay plan activation, read-only export window, JSON export |
| Entity master & KYB | `src/lib/kyb/`, `src/lib/onboarding.ts`, `/onboarding`, `/clients` | PAN / CIN verification (mock or Surepass), directors, GSTINs, DPDP consent link |
| Statutory applicability | `src/lib/engine/statutory-triggers.ts`, `thresholds.ts` | CARO, IFCoFR, Rule 11(g), Sec 138/139(2)/204/148, XBRL, CFS, 44AB, MSME AS, AQMM phase — each flag with a reason |
| Compliance calendar & tasks | `src/lib/engine/compliance-calendar.ts`, `/tasks`, `PATCH /api/v1/tasks` | GSTR-1 → IMS 14th → 3B, QRMP, TDS, tax audit, ROC chain (GC 05/2026), cost audit; maker → checker → EQCR → completed with UDIN gate |
| Proposals & e-sign | `src/lib/proposals.ts`, `/proposals`, `/sign/<token>` | Sec 144 group conflict gate, SA 210 letters, OTP e-signature with hash / mobile / IP |
| Signing desk | `/sign-desk`, `src/components/dsc-signer.tsx` | localhost emSigner / emBridge bridge (1585 / 1645 / 8080), signed-document register, UDIN gate |
| GST IMS workbench | `src/lib/gst/`, `/gst/ims`, `/gst/outward`, `POST /api/v1/gst/ims-adjudicate` | GSTR-2B JSON / CSV import, purchase-register three-way match, Sec 17(5) accept-and-reverse, pending caps, deemed-acceptance countdown, 2B recompute flag, 3B preview, offline-utility export, GSTR-1A pre-flight |
| Billing | `src/lib/billing/`, `/billing`, `/timesheets`, `/billing/fee-review` | GST invoices (CGST/SGST/IGST, 194J TDS), unbilled-work guard (Contract D), Razorpay links + webhook, timesheets, fee review with revision letter |
| Communications | `src/lib/comms/`, `/inbox`, `/broadcasts`, `/outbox`, `scripts/worker.ts` | WhatsApp Cloud API + SMTP adapters, outbox dispatcher with 24-h window and free-tier rules, inbound webhook and shared inbox, reminder engine (15/7/3/1 days, overdue invoices, unsigned proposals, IMS 48 h, partner digest), broadcast studio with template-category linter, AQMM Dim 3 log |
| Portal notices & extension | `extension/`, `/notices`, `/api/ext/*` | MV3 Chrome extension for lead capture and notice sync, API keys, client matching, resolution workflow |
| Zero-knowledge vault | `/clients/<id>/vault` | PBKDF2 + AES-256-GCM in the browser; server stores ciphertext only |
| AQMM v2.0 | `src/lib/aqmm/`, `/aqmm`, `/aqmm-check` | 8-dimension rubric with live evidence and suggested scores, overall level, Form 1 annexure; public diagnostic lead magnet |
| Audit execution | `src/lib/audit/`, `/audit` | engagements with templated papers (planning, CARO 21, IFCoFR, Rule 11(g), 3CD), SA 320 materiality, SA 315 risk matrix, seeded SA 530 sampling (random / systematic / MUS), SA 240 full-population JE tests with Benford, versioned SA 230 papers, maker-checker-EQCR, RCA tracker, report gates |
| Costing & XBRL | `src/lib/costing/`, `/costing` | CAS-mapped trial balance, ABC overhead apportionment, CRA-1 cost sheets, CRA-3 Part D, CRA-4 XBRL instance with checks |
| Documents | `src/lib/documents/`, `/clients/<id>/documents`, `/upload/<token>` | document requests on no-login upload links, local-disk store (Docker volume), chasers every 3 days for missing items that stop on completion, staff uploads, authenticated downloads with SHA-256 |
| Registers | `/registers/udin`, `/registers/dsc`, `/registers/cpe` | UDIN register with CSV export, DSC token expiry and check-out / check-in custody log, CPE hours per member |
| Account | `/signup`, `/forgot-password`, `/reset/<token>`, `/settings/password` | self-serve signup, email password reset (one-hour token, sessions revoked), password change |
| Email | `src/lib/comms/imap.ts` | IMAP polling of the firm mailbox into the shared inbox (matched by contact email, inline-image warning), SMTP replies |
| Ops | `/api/health`, `next.config.ts`, `src/middleware.ts`, `Dockerfile`, `docker-compose.yml` | security headers, CSP allowing the localhost signing agent, rate limiting, standalone build, Postgres schema generation, RLS policies |

## Run it

```bash
npm install
cp .env.example .env      # SQLite locally; leave SUREPASS_API_TOKEN blank to use the mock gateway
npm run setup             # prisma db push + seed (demo firm, 5 clients, leads)
npm run dev               # http://localhost:3100
npm test
```

Node 22 is expected on PATH (`~/.local/node/bin` on this machine).

## Architecture notes

* **Rule engines are pure functions** (no I/O) so every statutory decision is unit-testable and explainable; the UI shows the reason next to each flag for the working-paper file.
* **Money is stored in ₹ crore** as floats for threshold evaluation. Invoices (Stage 2) will use paise integers.
* **SQLite in dev, PostgreSQL in prod**: change the `datasource` provider and `DATABASE_URL`. No enums/arrays are used so the schema ports unchanged. Row-Level Security per `firmId` is added at the Postgres layer.
* **KYB provider is swappable**: the Surepass adapter's endpoint paths live in one file; Karza / Signzy adapters implement the same interface.
* **Demo sign-in**: `partner@demo.firm` (also `eqcr@`, `manager@`, `article1@`) with the password set in `prisma/seed.ts`.
* **Vault passphrase** is never stored anywhere; record it in the firm's own password manager. The server cannot recover vault entries.
* **Signing agent protocol**: emSigner / emBridge command names vary by build; `BRIDGE_COMMANDS` in `dsc-signer.tsx` is the one place to adapt. The diagnostic lists every port / scheme it tried.
* **Portal scrapers** read only what the logged-in practitioner can see and match table columns by header keywords, so a portal redesign degrades to "no rows found" rather than wrong data.

## Threshold caveat

The research brief quotes a raised ₹10 crore small-company limit for FY 2025-26. The notified Sec 2(85) rule we could verify is paid-up ≤ ₹4 Cr and turnover ≤ ₹40 Cr, which is what `thresholds.ts` uses. Confirm against the latest MCA notification before relying on CARO / IFCoFR exemptions.

## What still needs real-world calibration

* **Live-system contracts not exercised here**: Surepass response shapes, emSigner command vocabulary, government portal table layouts, Meta template approvals. Each lives in one adapter file.
* **Thresholds and rubric**: `thresholds.ts` (small-company limit) and `aqmm/rubric.ts` (level cut-offs) must be aligned to the current notifications and the ICAI Implementation Guide.
* **XBRL**: the generated instance uses taxonomy-style element names; the MCA validation tool is the authority.
* **Docker**: images written to the standard layout but not built here (no Docker on the build machine).

## Roadmap beyond the four stages

1. Gmail / Outlook OAuth (today: IMAP + SMTP with app passwords, which works for both).
2. Native Android / iOS apps for field staff and clients (the web app is responsive).
3. AI-assisted drafting for proposals, notice replies and circular summaries.
4. Document management with versioned client files and e-discovery for peer review.
