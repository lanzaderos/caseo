# Caseo

To start your Phoenix server:

* Run `mix setup` to install and set up dependencies. Node.js and npm are required to build assets.
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Self-hosted

Caseo se instala con Docker Compose (`compose.prod.yaml`): `core` (la aplicación), `db` (PostgreSQL) y `whatsmeow` (conector de WhatsApp). Guía de instalación: https://caseo-docs.lanzaderos.workers.dev (fuente en `docs/`, Starlight desplegado en Cloudflare Workers con `npm --prefix docs run deploy`).

## Asset linting and formatting

- Run `npm --prefix assets run lint` to lint JavaScript with Oxlint.
- Run `npm --prefix assets run format` to format JavaScript, CSS and asset configuration with Oxfmt.
- `mix assets.check` runs both asset checks and is included in `mix precommit`. `mix format` handles Elixir and HEEx.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Two-factor authentication and account recovery

Enable TOTP under **Settings → Two-factor authentication**. Enrollment requires
a recent sign-in. Scan the QR code or enter the setup key manually, then enter
a valid code from the authenticator app. Caseo displays
ten single-use recovery codes after enrollment. Save them before signing in
again. Turning TOTP on or off revokes existing sessions and pending sign-ins.

With TOTP enabled, an email magic link or password starts a five-minute
challenge. A fresh authenticator code or a recovery code completes sign-in.
The account allows five verification attempts per five-minute window, shared
across challenges. Recovery codes are consumed on use and leave TOTP enabled.
After signing in with a recovery code, use the recent session to disable TOTP
and enroll a new authenticator if needed. If both the authenticator and all
recovery codes are lost, email alone cannot restore access.

A passkey satisfies the second factor only when the server verifies the
WebAuthn assertion and its user-verification flag.

The endpoint's `SECRET_KEY_BASE` protects stored TOTP secrets, so deployments
sharing a database must share that key. Replacing it without migrating the
encrypted secrets requires affected users to sign in with a recovery code and
enroll TOTP again.


## Passkeys

Sign in recently to add, rename or revoke a passkey under **Settings → Passkeys**.
Once enrolled, choose **Sign in with a passkey** on the login page.

For local development, use `http://localhost:4000`. In production, run the
database migrations and set `PASSKEY_RP_ID` to the stable domain used for
passkeys, typically the same host as `PHX_HOST`. The allowed origin is
`https://` followed by `PHX_HOST`. Production passkeys are enabled when
`PASSKEY_RP_ID` is set. Changing the RP ID requires users to enroll again.

## Leads

Track people interested in your properties under **Interesados**. A lead has a
name, a phone number, an optional email, a source (Idealista, Fotocasa,
Pisos.com, Milanuncios, WhatsApp or other) and notes. Phone numbers are stored
in E.164; nine-digit numbers without a prefix are taken as Spanish. A phone
number is unique within an account.

Link a lead to any number of properties or rooms. Each link has its own status:
new, contacted, visit scheduled, visited, offer, closed, or discarded with a
reason. The property page groups its leads by status, and the property list
shows how many leads are still in play. Deleting a lead removes its links.

## Requirements and commission

Each property has requirements and a commission, set in the property form.
Requirements come from a fixed template (recent payslips, accepted contract
types, minimum income as a multiple of the rent, guarantor or rent insurance,
deposit and extra guarantee months, pets, smokers) plus one free-text
requirement that rejects discriminatory criteria. Rent-based requirements do not
apply to sales.

Sales charge a percentage of the price or a fixed amount. Rentals charge a
number of monthly rents, a percentage of the annual rent or a fixed amount, and
record who pays it (under Ley 12/2023, the landlord pays for a primary
residence). Either can add 21 % VAT. The property page and the property list
show the estimated commission; a property rented by rooms adds up its rooms.

A room can override the property's requirements and commission. Every lead
linked to a property or room gets its requirements as a checklist (met, not
met, pending), summarized as e.g. "3/4 requisitos" on the property page. Only
the outcome is stored, never the documents.

## Visits

Schedule a visit with **Agendar visita** on a lead's property link, either from
the lead page or from the property page. A visit has a date and time, a
duration and notes, and moves a new or contacted lead to "visit scheduled".
Statuses are scheduled, confirmed, done, no-show and cancelled. Rescheduling
keeps the previous times in the visit's history. When a visit is done, Caseo
offers to mark the lead as visited.

**Agendar visita** opens a dialog with two options: pick the date yourself (the
form suggests your free slots), or send the lead a booking link. Mark when you
hold visits under **Agenda → Disponibilidad**: time ranges on given days, split
into slots. A range can repeat every week, forever or until a date; leads see
weekly slots up to four weeks ahead. The booking link is public, works without an account, expires after
seven days and can be revoked; generating a new one revokes the previous one.
Copy it, or open WhatsApp with the message ready. The lead picks a free slot,
which then stops being offered to anyone else, and the visit waits for your
approval in the agenda.

**Agenda** lists upcoming visits by day and filters them by property. The
property and lead pages show their upcoming visits. Times are stored as local
wall-clock time (Spain).

## WhatsApp

Each owner links their own WhatsApp number under **WhatsApp → Vincular número**
by scanning a QR code, as with WhatsApp Web. Caseo talks to WhatsApp through
the `Caseo.Whatsapp.Provider` behaviour. The first provider is the whatsmeow
sidecar in `whatsmeow/` (unofficial: WhatsApp may ban the number); each account
stores its provider, so owners can move to the official Cloud API one by one.

Incoming messages reach `POST /api/whatsapp/:provider` and are stored in
Caseo's own format. Caseo only sends to people who wrote first or are the
owner's leads, records whether each sent message is a reply within 24 hours or
starts the conversation, and the sidecar paces and caps sends per number. See
the self-hosted guide (`docs/`) for the limits and the sidecar API.

The **WhatsApp** inbox lists the owner's conversations, updates in real time
and lets them reply. Each chat is matched to a lead by phone number; a side
panel shows the lead's properties, requirements and upcoming visits, creates
the lead if there is none, links properties (suggesting the one whose Idealista
listing the contact sent) and opens the "Agendar visita" dialog, which sends
the booking link from the linked number. Message times are shown in the
viewer's timezone. Only text is shown; photos, audio and documents appear as a
label.

## Licencia

Caseo se distribuye bajo la [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). Si modificas Caseo y lo ofreces como servicio a otras personas, debes publicar el código fuente de tus cambios bajo la misma licencia.
