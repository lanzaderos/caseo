defmodule CaseoWeb.PropertyLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Properties

  @attrs %{"name" => "Piso Centro", "rent" => "875,50", "available_on" => "2026-12-01"}

  test "redirects visitors to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/inmuebles")
    assert path == ~p"/users/log-in"
  end

  test "saves a valid form, edits the property and archives it", %{conn: conn} do
    scope = user_scope_fixture()
    conn = log_in_user(conn, scope.user)
    {:ok, new_view, _html} = live(conn, ~p"/inmuebles/nuevo")

    new_view
    |> form("#property-form", property: %{@attrs | "rent" => "0"})
    |> render_submit()

    assert has_element?(new_view, "#property_rent.input-error")
    assert Properties.list_properties(scope) == []

    assert {:ok, index, _html} =
             new_view
             |> form("#property-form", property: @attrs)
             |> render_submit()
             |> follow_redirect(conn, ~p"/inmuebles")

    assert [property] = Properties.list_properties(scope)
    selector = "#properties-#{property.id}"
    assert has_element?(index, selector)

    assert has_element?(index, "#new-property")

    assert has_element?(
             index,
             ~s(#workspace-navigation a[href="/inmuebles"][aria-current="location"])
           )

    {:ok, edit_view, _html} =
      index
      |> element("#edit-property-#{property.id}")
      |> render_click()
      |> follow_redirect(conn, ~p"/inmuebles/#{property.id}/editar")

    assert has_element?(edit_view, ~s(#property_rent[value="875,50"]))

    assert {:ok, index, _html} =
             edit_view
             |> form("#property-form", property: %{@attrs | "name" => "Piso Norte"})
             |> render_submit()
             |> follow_redirect(conn, ~p"/inmuebles")

    assert has_element?(index, selector <> " h2", "Piso Norte")
    index |> element("#archive-property-#{property.id}") |> render_click()
    refute has_element?(index, selector)

    index |> element("#archived-properties") |> render_click()
    assert_patch(index, ~p"/inmuebles?estado=archivados")
    assert has_element?(index, selector)
    refute has_element?(index, "#archive-property-#{property.id}")
  end

  test "creates a temporary rental for students and validates its dates and stay", %{conn: conn} do
    scope = user_scope_fixture()
    conn = log_in_user(conn, scope.user)
    {:ok, view, _html} = live(conn, ~p"/inmuebles/nuevo")

    attrs = Map.merge(@attrs, %{"rental_term" => "temporary", "for_students" => "true"})
    view |> form("#property-form", property: attrs) |> render_change()
    assert has_element?(view, "#property_available_until")
    assert has_element?(view, "#property_academic_year")

    invalid =
      Map.merge(attrs, %{
        "available_until" => "2026-11-30",
        "minimum_months" => "5",
        "maximum_months" => "3"
      })

    view |> form("#property-form", property: invalid) |> render_submit()
    assert has_element?(view, "#property_available_until.input-error")
    assert has_element?(view, "#property_maximum_months.input-error")
    assert Properties.list_properties(scope) == []

    valid =
      Map.merge(invalid, %{
        "available_until" => "2027-06-30",
        "maximum_months" => "7",
        "academic_year" => "2026–2027"
      })

    assert {:ok, index, _html} =
             view
             |> form("#property-form", property: valid)
             |> render_submit()
             |> follow_redirect(conn, ~p"/inmuebles")

    assert [property] = Properties.list_properties(scope)
    assert property.rental_term == :temporary
    assert property.available_until == ~D[2027-06-30]
    assert property.minimum_months == 5
    assert property.maximum_months == 7
    assert property.for_students
    assert property.academic_year == "2026–2027"
    assert has_element?(index, "#properties-#{property.id}")

    {:ok, edit, _html} = live(conn, ~p"/inmuebles/#{property.id}/editar")
    assert has_element?(edit, ~s(#property_academic_year[value="2026–2027"]))

    long_term = Map.merge(@attrs, %{"rental_term" => "long_term", "for_students" => "false"})
    edit |> form("#property-form", property: long_term) |> render_change()
    refute has_element?(edit, "#property_available_until")
    refute has_element?(edit, "#property_academic_year")

    assert {:ok, _index, _html} =
             edit
             |> form("#property-form", property: long_term)
             |> render_submit()
             |> follow_redirect(conn, ~p"/inmuebles")

    assert {:ok, updated} = Properties.fetch_property(scope, property.id)
    assert updated.rental_term == :long_term
    refute updated.for_students
    assert is_nil(updated.available_until)
    assert is_nil(updated.minimum_months)
    assert is_nil(updated.maximum_months)
    assert is_nil(updated.academic_year)
  end

  test "an authenticated account cannot see, edit or archive another owner's property" do
    owner = user_scope_fixture()
    other = user_scope_fixture()
    {:ok, foreign} = Properties.create_property(owner, @attrs)
    {:ok, own} = Properties.create_property(other, @attrs)
    owner_conn = log_in_user(build_conn(), owner.user)
    conn = log_in_user(build_conn(), other.user)

    {:ok, owner_view, _html} = live(owner_conn, ~p"/inmuebles")
    assert has_element?(owner_view, "#properties-#{foreign.id}")
    refute has_element?(owner_view, "#properties-#{own.id}")

    {:ok, view, _html} = live(conn, ~p"/inmuebles")
    assert has_element?(view, "#properties-#{own.id}")
    refute has_element?(view, "#properties-#{foreign.id}")

    assert {:error, {:redirect, %{to: path}}} =
             live(conn, ~p"/inmuebles/#{foreign.id}/editar")

    assert path == ~p"/inmuebles"
    render_click(view, "archive", %{"id" => to_string(foreign.id)})

    assert {:ok, unchanged} = Properties.fetch_property(owner, foreign.id)
    assert unchanged.archived_at == nil
    assert unchanged.name == @attrs["name"]
  end
end
