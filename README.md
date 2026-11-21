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

## Licencia

Caseo se distribuye bajo la [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). Si modificas Caseo y lo ofreces como servicio a otras personas, debes publicar el código fuente de tus cambios bajo la misma licencia.
