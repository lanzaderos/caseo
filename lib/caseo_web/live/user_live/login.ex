defmodule CaseoWeb.UserLive.Login do
  use CaseoWeb, :live_view

  alias Caseo.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} auth>
      <section aria-labelledby="login-title" class="space-y-6">
        <header class="space-y-2">
          <h1 id="login-title" class="auth-title">Log in</h1>
          <p class="workspace-muted text-sm leading-relaxed">
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Enter your email to receive a secure sign-in link.
            <% end %>
          </p>
        </header>

        <.form
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
          class="space-y-3"
        >
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            id="login_form_magic_email"
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn workspace-primary w-full">
            Log in with email
          </.button>
        </.form>

        <div class="workspace-divider space-y-3 border-t pt-4">
          <.form
            :if={Accounts.Passkeys.enabled?()}
            for={to_form(%{})}
            id="login-with-passkey"
            action={~p"/users/log-in/passkey"}
            data-passkey="authenticate"
            data-options={~p"/users/log-in/passkey/options"}
            phx-hook="Passkey"
            phx-update="ignore"
          >
            <.button disabled data-passkey-submit class="btn auth-secondary w-full">
              Sign in with a passkey
            </.button>
            <p data-passkey-status class="mt-2 text-sm text-error empty:hidden" role="status"></p>
          </.form>

          <details class="group" open={!!Phoenix.Flash.get(@flash, :error)}>
            <summary class="workspace-muted flex min-h-11 cursor-pointer list-none items-center justify-between gap-2 rounded-lg px-2 text-sm font-medium hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 [&::-webkit-details-marker]:hidden">
              Log in with a password
              <.icon name="hero-chevron-down" class="size-4 group-open:rotate-180" />
            </summary>
            <.form
              for={@form}
              id="login_form_password"
              action={~p"/users/log-in"}
              phx-submit="submit_password"
              phx-trigger-action={@trigger_submit}
              class="space-y-3 pt-3"
            >
              <.input
                readonly={!!@current_scope}
                field={@form[:email]}
                id="login_form_password_email"
                type="email"
                label="Email"
                autocomplete="username"
                spellcheck="false"
                required
              />
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                autocomplete="current-password"
                spellcheck="false"
                required
              />
              <.button
                class="btn workspace-primary w-full"
                name={@form[:remember_me].name}
                value="true"
              >
                Log in and stay logged in
              </.button>
              <.button class="btn auth-secondary w-full">
                Log in only this time
              </.button>
            </.form>
          </details>
        </div>

        <p :if={!@current_scope} class="workspace-muted text-sm">
          Don't have an account?
          <.link navigate={~p"/users/register"} class="auth-link">Sign up</.link>
        </p>

        <div :if={local_mail_adapter?()} class="workspace-muted text-xs leading-relaxed">
          You are running the local mail adapter. <.link href="/dev/mailbox" class="auth-link">Open the mailbox</.link>.
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:caseo, Caseo.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
