defmodule Caseo.VisitsTest do
  use Caseo.DataCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Leads
  alias Caseo.Properties
  alias Caseo.Visits

  setup do
    scope = user_scope_fixture()

    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => "Piso compartido",
        "mode" => "rooms",
        "street" => "Calle Mayor 12",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid",
        "rooms" => [%{"name" => "Habitación sur", "rent" => "450"}]
      })

    [room] = property.rooms
    {:ok, lead} = Leads.create_lead(scope, %{"name" => "Ana", "phone" => "612345678"})
    {:ok, interest} = Leads.add_interest(scope, lead.id, property.id, room.id)

    %{scope: scope, property: property, room: room, lead: lead, interest: interest}
  end

  test "schedules, reschedules and cancels a visit linked to the right lead and room", ctx do
    starts_at = in_days(2, ~T[10:30:00])

    {:ok, visit} =
      Visits.create_visit(ctx.scope, ctx.interest.id, %{
        "starts_at" => starts_at,
        "notes" => "Llamar antes"
      })

    {:ok, visit} = Visits.fetch_visit(ctx.scope, visit.id)
    assert visit.interest.lead.id == ctx.lead.id
    assert visit.interest.property.id == ctx.property.id
    assert visit.interest.room.id == ctx.room.id
    assert {:ok, %{status: :visit_scheduled}} = Leads.fetch_interest(ctx.scope, ctx.interest.id)

    assert [%{id: id}] = Visits.list_pending_visits(ctx.scope, ctx.property.id)
    assert id == visit.id

    new_time = in_days(3, ~T[17:00:00])
    {:ok, visit} = Visits.update_visit(ctx.scope, visit.id, %{"starts_at" => new_time})
    assert visit.starts_at == new_time
    assert [%{"from" => from}] = visit.reschedules
    assert from == NaiveDateTime.to_iso8601(starts_at)

    {:ok, _visit} = Visits.update_visit(ctx.scope, visit.id, %{"status" => "cancelled"})
    assert Visits.list_pending_visits(ctx.scope, ctx.property.id) == []
    assert [%{status: :cancelled}] = Visits.list_visits(ctx.scope, property_id: ctx.property.id)
  end

  test "other owners cannot list, open or change a visit", ctx do
    other = user_scope_fixture()

    {:ok, visit} =
      Visits.create_visit(ctx.scope, ctx.interest.id, %{"starts_at" => in_days(1, ~T[09:00:00])})

    assert Visits.list_visits(other) == []
    assert Visits.list_pending_visits(other, ctx.property.id) == []
    assert {:error, :not_found} = Visits.fetch_visit(other, visit.id)
    assert {:error, :not_found} = Visits.update_visit(other, visit.id, %{"status" => "cancelled"})

    assert {:error, :not_found} =
             Visits.create_visit(other, ctx.interest.id, %{
               "starts_at" => in_days(1, ~T[09:00:00])
             })
  end

  test "deleting the lead removes their visits", ctx do
    {:ok, _visit} =
      Visits.create_visit(ctx.scope, ctx.interest.id, %{"starts_at" => in_days(1, ~T[09:00:00])})

    :ok = Leads.delete_lead(ctx.scope, ctx.lead.id)
    assert Visits.list_visits(ctx.scope) == []
  end

  defp in_days(days, time) do
    Date.utc_today() |> Date.add(days) |> NaiveDateTime.new!(time)
  end
end
