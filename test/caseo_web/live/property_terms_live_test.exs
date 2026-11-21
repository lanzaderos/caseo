defmodule CaseoWeb.PropertyTermsLiveTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Leads
  alias Caseo.Properties

  test "sets requirements in the form and checks them on each lead", %{conn: conn} do
    scope = user_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/inmuebles/nuevo")

    view
    |> form("#property-form",
      property: %{
        name: "Piso centro",
        mode: "rental",
        rent: "900",
        street: "Calle Mayor 12",
        municipality: "Madrid",
        postal_code: "28013",
        province: "Madrid",
        requirements: %{payslips: "2", guarantee: "true"},
        commission: %{kind: "months"}
      }
    )
    |> render_change()

    view
    |> form("#property-form",
      property: %{commission: %{kind: "months", value: "1", vat: "true", payer: "tenant"}}
    )
    |> render_submit()

    [property] = Properties.list_properties(scope)
    assert property.requirements.payslips == 2
    assert property.commission.payer == :tenant

    {:ok, index, _html} = live(conn, ~p"/inmuebles")
    assert render(element(index, "#commission-#{property.id}")) =~ "1089,00 €"

    {:ok, lead} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612345678"})
    {:ok, interest} = Leads.add_interest(scope, lead.id, property.id)

    {:ok, lead_view, _html} = live(conn, ~p"/interesados/#{lead.id}")
    assert has_element?(lead_view, "#interest-#{interest.id}-check-payslips")

    lead_view
    |> form("#interest-form-#{interest.id}",
      interest: %{status: "contacted", checks: %{payslips: "met", guarantee: "pending"}}
    )
    |> render_submit()

    assert [%{checks: %{"payslips" => "met"}}] = Leads.list_property_interests(scope, property.id)

    {:ok, detail, _html} = live(conn, ~p"/inmuebles/#{property.id}")
    assert has_element?(detail, "#requirement-payslips")
    assert render(element(detail, "#property-interest-#{interest.id}-checks")) =~ "1/2 requisitos"
  end
end
