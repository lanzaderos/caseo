defmodule CaseoWeb.PropertyAddressControllerTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Properties.AddressSearch

  test "returns structured postal suggestions for a signed-in owner", %{conn: conn} do
    Req.Test.stub(AddressSearch, fn request ->
      assert request.request_path == "/geocoder/api/geocoder/candidates"
      assert Plug.Conn.fetch_query_params(request).query_params["q"] == "Calle Mayor 12 Madrid"

      Req.Test.json(request, [
        %{"type" => "municipio", "address" => "Madrid"},
        %{
          "type" => "portal",
          "address" => "CALLE MAYOR 12, Madrid",
          "muni" => "Madrid",
          "province" => "Madrid",
          "postalCode" => "28013",
          "lat" => 40.41649,
          "lng" => -3.70615,
          "refCatastral" => "excluded"
        }
      ])
    end)

    conn =
      conn
      |> log_in_user(user_fixture())
      |> get(~p"/inmuebles/direcciones", address_query: "Calle Mayor 12 Madrid")

    assert json_response(conn, 200) == %{
             "addresses" => [
               %{
                 "street" => "CALLE MAYOR 12",
                 "municipality" => "Madrid",
                 "province" => "Madrid",
                 "postal_code" => "28013",
                 "latitude" => 40.41649,
                 "longitude" => -3.70615
               }
             ]
           }

    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "requires authentication and returns an error when the provider is down", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/inmuebles/direcciones", address_query: "Calle Mayor")) ==
             ~p"/users/log-in"

    Req.Test.stub(AddressSearch, &Plug.Conn.send_resp(&1, 503, ""))

    conn = log_in_user(conn, user_fixture())

    assert conn
           |> get(~p"/inmuebles/direcciones", address_query: "abc")
           |> json_response(200) == %{"addresses" => []}

    assert conn
           |> get(~p"/inmuebles/direcciones", address_query: "Calle Mayor")
           |> json_response(503) == %{"addresses" => []}
  end
end
