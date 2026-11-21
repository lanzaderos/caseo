defmodule Caseo.LeadsTest do
  use Caseo.DataCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Leads
  alias Caseo.Leads.Lead
  alias Caseo.Properties

  test "normalizes phones to E.164" do
    assert Lead.normalize_phone("612 345 678") == "+34612345678"
    assert Lead.normalize_phone("0034 612-345-678") == "+34612345678"
    assert Lead.normalize_phone("+44 (20) 7946 0958") == "+442079460958"
  end

  test "links a lead to two properties with different statuses" do
    scope = user_scope_fixture()
    flat = property(scope, "Piso centro")
    shared = rooms_property(scope)
    [room] = shared.rooms

    {:ok, lead} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612 345 678"})
    assert lead.phone == "+34612345678"

    {:ok, flat_interest} = Leads.add_interest(scope, lead.id, flat.id)
    {:ok, _room_interest} = Leads.add_interest(scope, lead.id, shared.id, room.id)
    assert {:error, :already_linked} = Leads.add_interest(scope, lead.id, flat.id)

    assert {:ok, %{status: :visit_scheduled}} =
             Leads.update_interest(scope, flat_interest.id, %{"status" => "visit_scheduled"})

    {:ok, lead} = Leads.fetch_lead(scope, lead.id)
    assert Enum.map(lead.interests, & &1.status) == [:visit_scheduled, :new]

    assert {:error, changeset} =
             Leads.update_interest(scope, flat_interest.id, %{"status" => "discarded"})

    assert %{discard_reason: [_]} = errors_on(changeset)

    assert {:ok, %{status: :discarded, discard_reason: "Sin nómina"}} =
             Leads.update_interest(scope, flat_interest.id, %{
               "status" => "discarded",
               "discard_reason" => "Sin nómina"
             })

    assert Leads.count_by_property(scope) == %{shared.id => 1}

    assert :ok = Leads.delete_lead(scope, lead.id)
    assert Leads.list_property_interests(scope, shared.id) == []
  end

  test "a phone is unique per owner but can repeat across owners" do
    scope = user_scope_fixture()
    other = user_scope_fixture()

    assert {:ok, _} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612345678"})

    assert {:error, changeset} =
             Leads.create_lead(scope, %{"name" => "Ana B", "phone" => "+34 612 345 678"})

    assert %{phone: ["ya tienes un interesado con este teléfono"]} = errors_on(changeset)
    assert {:ok, _} = Leads.create_lead(other, %{"name" => "Ana", "phone" => "612345678"})
  end

  test "other owners cannot list, open, change or link someone else's leads" do
    scope = user_scope_fixture()
    other = user_scope_fixture()
    flat = property(scope, "Piso centro")
    other_flat = property(other, "Ático")
    other_rooms = rooms_property(other)
    [other_room] = other_rooms.rooms

    {:ok, lead} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612345678"})
    {:ok, interest} = Leads.add_interest(scope, lead.id, flat.id)

    assert Leads.list_leads(other) == []
    assert Leads.list_property_interests(other, flat.id) == []
    assert {:error, :not_found} = Leads.fetch_lead(other, lead.id)
    assert {:error, :not_found} = Leads.update_lead(other, lead.id, %{"name" => "X"})
    assert {:error, :not_found} = Leads.delete_lead(other, lead.id)
    assert {:error, :not_found} = Leads.add_interest(other, lead.id, other_flat.id)

    assert {:error, :not_found} =
             Leads.update_interest(other, interest.id, %{"status" => "closed"})

    assert {:error, :not_found} = Leads.delete_interest(other, interest.id)

    # The owner cannot link their lead to another owner's property or room.
    assert {:error, :not_found} = Leads.add_interest(scope, lead.id, other_flat.id)
    assert {:error, :not_found} = Leads.add_interest(scope, lead.id, flat.id, other_room.id)
  end

  defp property(scope, name) do
    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => name,
        "mode" => "rental",
        "rent" => "900",
        "street" => "Calle Mayor 12",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid"
      })

    property
  end

  defp rooms_property(scope) do
    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => "Piso compartido",
        "mode" => "rooms",
        "street" => "Calle Mayor 14",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid",
        "rooms" => [%{"name" => "Habitación sur", "rent" => "450"}]
      })

    property
  end
end
