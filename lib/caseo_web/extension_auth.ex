defmodule CaseoWeb.ExtensionAuth do
  @moduledoc """
  Authenticates browser extension API requests with an
  `Authorization: Bearer <token>` header and assigns `:current_scope`.
  """
  @behaviour Plug

  import Plug.Conn

  alias Caseo.Accounts
  alias Caseo.Accounts.Scope

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Accounts.User{} = user <- Accounts.get_user_by_extension_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:extension_token, token)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(:unauthorized, ~s({"error":"unauthorized"}))
        |> halt()
    end
  end
end
