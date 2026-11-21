defmodule CaseoWeb.ExtensionController do
  @moduledoc """
  Connects the browser extension to the signed-in account.

  The extension opens `/extension/connect?state=...` in a normal tab, so the
  usual sign-in flow (magic link, password, passkey) applies. After the user
  confirms, the response page carries the token in `#extension-token`, where
  the extension reads it and checks `state`. The token never appears in a URL.
  """
  use CaseoWeb, :controller

  alias Caseo.Accounts

  plug :protect_sensitive_pages

  @state ~r/\A[A-Za-z0-9_-]{16,128}\z/

  def new(conn, %{"state" => state}) when is_binary(state) do
    if state =~ @state, do: render(conn, :new, state: state), else: invalid(conn)
  end

  def new(conn, _params), do: invalid(conn)

  def create(conn, %{"state" => state}) when is_binary(state) do
    if state =~ @state do
      token = Accounts.generate_extension_token(conn.assigns.current_scope.user)
      render(conn, :connected, state: state, token: token)
    else
      invalid(conn)
    end
  end

  def create(conn, _params), do: invalid(conn)

  defp invalid(conn) do
    conn
    |> put_status(:bad_request)
    |> render(:invalid)
  end

  defp protect_sensitive_pages(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end
end
