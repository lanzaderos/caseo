# Caseo

To start your Phoenix server:

* Run `mix setup` to install and set up dependencies. Node.js and npm are required to build assets.
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

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
WebAuthn assertion and its user-verification flag. Passkey registration and
sign-in are tracked separately in [issue #4](https://github.com/lanzaderos/caseo/issues/4).

The endpoint's `SECRET_KEY_BASE` protects stored TOTP secrets, so deployments
sharing a database must share that key. Replacing it without migrating the
encrypted secrets requires affected users to sign in with a recovery code and
enroll TOTP again.
