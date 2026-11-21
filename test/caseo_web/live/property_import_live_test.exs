defmodule CaseoWeb.PropertyImportLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Properties
  alias Caseo.Properties.Imports
  alias Caseo.Properties.ListingImages

  @image "https://img4.idealista.com/blur/WEB_DETAIL_TOP-L-P/0/id.pro.es.image.master/c9/00/35/1494379906.jpg"
  @jpeg <<255, 216, 255, 224>> <> :binary.copy(<<0>>, 64)

  @payload %{
    "url" => "https://www.idealista.com/inmueble/777/",
    "title" => "Piso en alquiler en calle Mayor",
    "price" => "950 €/mes",
    "address" => ["Calle Mayor 3", "Barrio Sol", "Madrid", "Madrid capital, Madrid"],
    "images" => [@image]
  }

  setup %{conn: conn} do
    scope = user_scope_fixture()
    {:ok, listing_import} = Imports.create(scope, @payload)
    %{scope: scope, listing_import: listing_import, conn: log_in_user(conn, scope.user)}
  end

  test "shows an editable preview with the listing data", %{conn: conn, listing_import: imp} do
    {:ok, view, _html} = live(conn, ~p"/importaciones/#{imp.id}")

    assert has_element?(view, "#listing-import-source[href='#{imp.url}']")
    assert has_element?(view, "#property_name[value='Piso en alquiler en calle Mayor']")
    assert has_element?(view, "#property_rent[value='950']")
    assert has_element?(view, "#property_street[value='Calle Mayor 3']")
    assert has_element?(view, "#listing-image-0[checked]")
    assert has_element?(view, "#save-property", "Crear borrador")
    refute has_element?(view, "#listing-import-matches")
  end

  test "requires sign-in and hides other owners' imports", %{listing_import: imp} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/importaciones/#{imp.id}")

    other = log_in_user(build_conn(), user_fixture())
    assert {:error, {:redirect, %{to: "/inmuebles"}}} = live(other, ~p"/importaciones/#{imp.id}")
  end

  test "creates a draft after completing missing data and authorizing photos", %{
    conn: conn,
    scope: scope,
    listing_import: imp
  } do
    Req.Test.stub(ListingImages, &Plug.Conn.send_resp(&1, 200, @jpeg))
    {:ok, view, _html} = live(conn, ~p"/importaciones/#{imp.id}")

    view
    |> form("#property-form", property: %{"postal_code" => "28013"}, images: [@image])
    |> render_submit()

    assert has_element?(view, "#images-error")
    assert Properties.list_properties(scope) == []

    assert {:ok, detail, html} =
             view
             |> form("#property-form",
               property: %{"postal_code" => "28013"},
               images: [@image],
               reuse_authorized: "true"
             )
             |> render_submit()
             |> follow_redirect(conn)

    assert html =~ "Borrador creado con 1 foto"
    assert has_element?(detail, "#draft-notice")
    assert [property] = Properties.list_properties(scope)
    assert property.status == :draft
    assert property.listing_external_id == "777"

    detail |> element("#mark-ready") |> render_click()
    refute has_element?(detail, "#draft-notice")
  end

  test "warns about a repeated listing and links it instead", %{
    conn: conn,
    scope: scope,
    listing_import: imp
  } do
    {:ok, property, 0} =
      Imports.confirm(
        scope,
        imp,
        %{
          "name" => "Ya importado",
          "mode" => "rental",
          "rent" => "900",
          "for_students" => "false",
          "street" => "Calle Mayor 3",
          "municipality" => "Madrid",
          "postal_code" => "28013",
          "province" => "Madrid"
        },
        []
      )

    {:ok, again} = Imports.create(scope, @payload)
    {:ok, view, _html} = live(conn, ~p"/importaciones/#{again.id}")

    assert has_element?(view, "#listing-import-matches", "Ya importado")

    assert {:ok, _detail, html} =
             view
             |> form("#listing-import-link", target: "property:#{property.id}")
             |> render_submit()
             |> follow_redirect(conn, ~p"/inmuebles/#{property.id}")

    assert html =~ "Anuncio vinculado"
  end

  test "discarding the import creates nothing", %{conn: conn, scope: scope, listing_import: imp} do
    {:ok, view, _html} = live(conn, ~p"/importaciones/#{imp.id}")

    assert {:ok, _index, _html} =
             view |> element("#discard-import") |> render_click() |> follow_redirect(conn)

    assert Properties.list_properties(scope) == []
    assert {:error, :not_found} = Imports.fetch_pending(scope, imp.id)
  end
end
