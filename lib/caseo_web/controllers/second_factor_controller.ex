defmodule CaseoWeb.SecondFactorController do
  use CaseoWeb, :controller

  alias Caseo.Accounts
  alias Caseo.Accounts.SecondFactor
  alias CaseoWeb.UserAuth

  plug :protect_sensitive_pages
  plug :require_recent_auth when action in [:settings, :enable, :disable]

  def challenge(conn, _params) do
    if SecondFactor.pending?(get_session(conn, :second_factor_challenge)) do
      render(conn, :challenge)
    else
      expired_challenge(conn)
    end
  end

  def verify(conn, %{"factor_code" => code}) when is_binary(code) do
    case SecondFactor.complete_login(get_session(conn, :second_factor_challenge) || "", code) do
      {:session, user, token} ->
        params = %{"remember_me" => to_string(get_session(conn, :second_factor_remember_me))}
        UserAuth.finish_login(conn, user, token, params)

      {:error, :expired} ->
        expired_challenge(conn)

      {:error, reason} ->
        conn
        |> put_flash(:error, factor_error(reason))
        |> redirect(to: ~p"/users/second-factor")
    end
  end

  def verify(conn, _params), do: challenge(conn, %{})

  def settings(conn, _params) do
    user = conn.assigns.current_scope.user

    if SecondFactor.enabled?(user) do
      render(conn, :settings, setup: nil)
    else
      render(conn, :settings, setup: SecondFactor.setup(get_session(conn, :user_token)))
    end
  end

  def enable(conn, %{"setup_ticket" => ticket, "factor_code" => code})
      when is_binary(ticket) and is_binary(code) do
    case SecondFactor.enable(get_session(conn, :user_token), ticket, String.trim(code)) do
      {:ok, codes, tokens} ->
        UserAuth.disconnect_sessions(tokens)

        conn
        |> UserAuth.clear_authentication()
        |> assign(:current_scope, nil)
        |> render(:recovery_codes, codes: codes)

      {:error, reason} ->
        settings_error(conn, reason)
    end
  end

  def enable(conn, _params), do: settings_error(conn, :invalid)

  def disable(conn, _params) do
    case SecondFactor.disable(get_session(conn, :user_token)) do
      {:ok, tokens} ->
        UserAuth.disconnect_sessions(tokens)

        conn
        |> UserAuth.clear_authentication()
        |> put_flash(:info, "Two-factor authentication was disabled. Sign in again to continue.")
        |> redirect(to: ~p"/users/log-in")

      {:error, reason} ->
        settings_error(conn, reason)
    end
  end

  defp protect_sensitive_pages(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end

  defp require_recent_auth(conn, _opts) do
    if Accounts.sudo_mode?(conn.assigns.current_scope.user, -10) do
      conn
    else
      conn |> settings_error(:reauthenticate) |> halt()
    end
  end

  defp settings_error(conn, :reauthenticate) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings/second-factor")
    |> put_flash(:error, "Sign in again to change two-factor authentication.")
    |> redirect(to: ~p"/users/log-in")
  end

  defp settings_error(conn, reason) do
    conn
    |> put_flash(:error, factor_error(reason))
    |> redirect(to: ~p"/users/settings/second-factor")
  end

  defp expired_challenge(conn) do
    conn
    |> delete_session(:second_factor_challenge)
    |> delete_session(:second_factor_remember_me)
    |> put_flash(:error, "This sign-in attempt expired. Sign in again to get a new challenge.")
    |> redirect(to: ~p"/users/log-in")
  end

  defp factor_error(:rate_limited), do: "Too many attempts. Wait five minutes and try again."
  defp factor_error(:invalid), do: "The code or setup session is invalid or has expired."
end
