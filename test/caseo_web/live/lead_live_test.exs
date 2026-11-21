defmodule CaseoWeb.LeadLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Leads
  alias Caseo.Properties

  test "creates a lead, links a property and tracks its status", %{conn: conn} do
    scope = user_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => "Piso centro",
        "mode" => "rental",
        "rent" => "900",
        "street" => "Calle Mayor 12",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid"
      })

    {:ok, view, _html} = live(conn, ~p"/interesados")
    assert has_element?(view, "#leads-empty")

    {:ok, view, _html} =
      view
      |> form("#lead-form", lead: %{name: "Ana", phone: "612 345 678", source: "idealista"})
      |> render_submit()
      |> follow_redirect(conn)

    [lead] = Leads.list_leads(scope)
    assert lead.phone == "+34612345678"
    assert has_element?(view, "#lead-interests-empty")

    view |> form("#link-form", link: %{target: to_string(property.id)}) |> render_submit()
    [interest] = Leads.list_property_interests(scope, property.id)
    assert has_element?(view, "#interest-form-#{interest.id}")

    view
    |> form("#interest-form-#{interest.id}", interest: %{status: "discarded"})
    |> render_change()

    assert has_element?(view, "#interest-#{interest.id}_discard_reason")

    view
    |> form("#interest-form-#{interest.id}",
      interest: %{status: "discarded", discard_reason: "Sin nómina"}
    )
    |> render_submit()

    assert [%{status: :discarded}] = Leads.list_property_interests(scope, property.id)

    {:ok, detail, _html} = live(conn, ~p"/inmuebles/#{property.id}")
    assert has_element?(detail, "#leads-discarded #property-interest-#{interest.id}")

    {:ok, _} = Leads.update_interest(scope, interest.id, %{"status" => "contacted"})
    {:ok, index, _html} = live(conn, ~p"/inmuebles")
    assert render(element(index, "#lead-count-#{property.id}")) =~ "1 interesado"
  end

  test "another owner cannot open a lead", %{conn: conn} do
    {:ok, lead} =
      Leads.create_lead(user_scope_fixture(), %{"name" => "Ana", "phone" => "612345678"})

    conn = log_in_user(conn, user_fixture())

    assert {:error, {:live_redirect, %{to: "/interesados"}}} =
             live(conn, ~p"/interesados/#{lead.id}")
  end
end
