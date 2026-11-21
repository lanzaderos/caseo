defmodule CaseoWeb.PasskeyController do
  use CaseoWeb, :controller

  alias Caseo.Accounts
  alias Caseo.Accounts.Passkeys
  alias CaseoWeb.UserAuth

  plug :put_layout, false
  plug :prepare_request

  plug :require_recent_auth
       when action in [:settings, :registration_options, :register, :rename, :revoke]

  def settings(conn, _params) do
    render(conn, :settings,
      form: Phoenix.Component.to_form(%{"name" => ""}),
      passkeys: Passkeys.list(conn.assigns.current_scope.user)
    )
  end

  def registration_options(conn, _params) do
    conn = ensure_binding(conn)

    json(
      conn,
      Passkeys.registration_options(conn.assigns.current_scope.user, challenge_binding(conn))
    )
  end

  def register(conn, params) do
    case Passkeys.register(get_session(conn, :user_token), challenge_binding(conn), params) do
      {:ok, _passkey} ->
        conn
        |> put_flash(:info, "Passkey added.")
        |> json(%{location: ~p"/users/settings/passkeys"})

      {:error, :reauthenticate} ->
        reauthenticate(conn)

      {:error, _} ->
        failed(conn, "Could not add the passkey. Check the name and try again.")
    end
  end

  def rename(conn, %{"id" => id} = params) do
    conn
    |> management_result(
      Passkeys.rename(get_session(conn, :user_token), id, params),
      "Passkey renamed."
    )
  end

  def revoke(conn, %{"id" => id}) do
    conn
    |> management_result(Passkeys.revoke(get_session(conn, :user_token), id), "Passkey revoked.")
  end

  def authentication_options(conn, _params) do
    conn = ensure_binding(conn)
    json(conn, Passkeys.authentication_options(challenge_binding(conn)))
  end

  def authenticate(conn, params) do
    user_id = conn.assigns.current_scope && conn.assigns.current_scope.user.id

    case Passkeys.authenticate(challenge_binding(conn), user_id, params) do
      {:ok, {user, token}} ->
        conn
        |> delete_session(:passkey_nonce)
        |> UserAuth.finish_login(user, token, %{})

      {:error, _} ->
        failed(conn, "Could not sign in with that passkey. Try again or use your email.")
    end
  end

  defp prepare_request(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if Passkeys.enabled?() do
      conn
    else
      conn |> send_resp(404, "") |> halt()
    end
  end

  defp require_recent_auth(conn, _opts) do
    if Accounts.sudo_mode?(conn.assigns.current_scope.user, -10) do
      conn
    else
      conn |> reauthenticate() |> halt()
    end
  end

  defp reauthenticate(conn) do
    conn =
      conn
      |> put_session(:user_return_to, ~p"/users/settings/passkeys")
      |> put_flash(:error, "Sign in again to manage your passkeys.")

    if action_name(conn) in [:registration_options, :register] do
      json(conn, %{location: ~p"/users/log-in"})
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end

  defp management_result(conn, {:ok, _passkey}, message) do
    conn |> put_flash(:info, message) |> redirect(to: ~p"/users/settings/passkeys")
  end

  defp management_result(conn, {:error, :reauthenticate}, _message), do: reauthenticate(conn)

  defp management_result(conn, {:error, _}, _message) do
    conn
    |> put_flash(:error, "Could not update the passkey. Check the name and try again.")
    |> redirect(to: ~p"/users/settings/passkeys")
  end

  defp ensure_binding(conn) do
    if get_session(conn, :passkey_nonce) do
      conn
    else
      put_session(conn, :passkey_nonce, :crypto.strong_rand_bytes(32))
    end
  end

  defp challenge_binding(conn) do
    with nonce when is_binary(nonce) <- get_session(conn, :passkey_nonce) do
      :crypto.hash(:sha256, nonce <> (get_session(conn, :user_token) || <<>>))
    end
  end

  defp failed(conn, message),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: message})
end
