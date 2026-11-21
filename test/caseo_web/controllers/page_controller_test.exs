defmodule CaseoWeb.PageControllerTest do
  use CaseoWeb.ConnCase

  test "public landing links to registration and login", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-register") |> LazyHTML.attribute("href") ==
             [~p"/users/register"]

    assert document |> LazyHTML.query("#landing-login") |> LazyHTML.attribute("href") ==
             [~p"/users/log-in"]
  end

  test "signed-in landing links to properties and account settings", context do
    %{conn: conn} = register_and_log_in_user(context)
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-properties") |> LazyHTML.attribute("href") ==
             [~p"/inmuebles"]

    assert document |> LazyHTML.query("#header-properties") |> LazyHTML.attribute("href") ==
             [~p"/inmuebles"]

    assert document |> LazyHTML.query("#landing-settings") |> LazyHTML.attribute("href") ==
             [~p"/users/settings"]

    assert Enum.empty?(LazyHTML.query(document, "#landing-register, #landing-login"))
  end
end
