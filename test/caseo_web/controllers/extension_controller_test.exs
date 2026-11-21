defmodule CaseoWeb.ExtensionControllerTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Accounts
  alias Caseo.Accounts.Scope
  alias Caseo.Properties.Imports

  @state "abcdefghijklmnop1234"
  @listing %{
    "url" => "https://www.idealista.com/inmueble/123456789/?xtmc=1",
    "title" => "Piso en alquiler en calle Mayor",
    "price" => "1.200 €/mes",
    "features" => ["75 m²", "3 hab."]
  }

  describe "connect" do
    test "requires sign-in and returns to the connect page afterwards", %{conn: conn} do
      conn = get(conn, ~p"/extension/connect?state=#{@state}")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == "/extension/connect?state=#{@state}"
    end

    test "issues a token only after the user confirms", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      page = conn |> get(~p"/extension/connect?state=#{@state}") |> html_response(200)
      assert page =~ "extension-connect-form"
      refute page =~ "extension-token"

      conn = post(conn, ~p"/extension/connect", %{"state" => @state})
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      [element] =
        conn
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#extension-token")
        |> Enum.to_list()

      assert [@state] = LazyHTML.attribute(element, "data-state")
      assert [token] = LazyHTML.attribute(element, "data-token")
      assert Accounts.get_user_by_extension_token(token).id == user.id
    end

    test "rejects a missing or malformed state", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert conn |> get(~p"/extension/connect") |> html_response(400)
      assert conn |> get(~p"/extension/connect?state=short") |> html_response(400)
      assert conn |> post(~p"/extension/connect", %{"state" => "a b"}) |> html_response(400)
    end
  end

  describe "API" do
    setup %{conn: conn} do
      user = user_fixture()
      token = Accounts.generate_extension_token(user)
      %{user: user, token: token, api: put_req_header(conn, "authorization", "Bearer " <> token)}
    end

    test "rejects requests without a valid token", %{conn: conn} do
      assert conn |> get(~p"/api/extension/me") |> json_response(401)

      assert conn
             |> put_req_header("authorization", "Bearer nope")
             |> get(~p"/api/extension/me")
             |> json_response(401)
    end

    test "returns the connected account", %{api: api, user: user} do
      assert %{"email" => email} = api |> get(~p"/api/extension/me") |> json_response(200)
      assert email == user.email
    end

    test "stores the listing and returns the preview path", %{api: api, user: user} do
      assert %{"id" => id, "preview_path" => path} =
               api |> post(~p"/api/extension/imports", @listing) |> json_response(201)

      assert path == "/importaciones/#{id}"

      assert {:ok, _} =
               Imports.fetch_pending(Scope.for_user(user), id)
    end

    test "rejects pages that are not Idealista listings", %{api: api} do
      assert %{"errors" => %{"url" => [_]}} =
               api
               |> post(~p"/api/extension/imports", %{
                 @listing
                 | "url" => "https://example.com/inmueble/1/"
               })
               |> json_response(422)
    end

    test "disconnecting revokes the token", %{api: api, token: token} do
      assert api |> delete(~p"/api/extension/session") |> response(204)
      assert Accounts.get_user_by_extension_token(token) == nil
    end
  end
end
