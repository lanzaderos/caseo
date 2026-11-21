defmodule Caseo.Visits do
  @moduledoc """
  Schedules and tracks the owner's visits. A visit belongs to a lead's
  interest in a property or room, and every query is scoped through the lead's
  owner.
  """

  import Ecto.Query

  alias Caseo.Accounts.Scope
  alias Caseo.Leads
  alias Caseo.Leads.Interest
  alias Caseo.Leads.Lead
  alias Caseo.Repo
  alias Caseo.Visits.Visit

  @preloads [interest: [:lead, :property, :room]]

  @doc """
  Lists the owner's visits from `from` (default: today) onwards, soonest
  first. Pass `property_id` or `lead_id` to narrow them.
  """
  @spec list_visits(Scope.t(), keyword()) :: [Visit.t()]
  def list_visits(scope, opts \\ []) do
    from = Keyword.get(opts, :from, NaiveDateTime.beginning_of_day(NaiveDateTime.local_now()))

    scope
    |> owned_visits()
    |> where([v], v.starts_at >= ^from)
    |> filter_property(Keyword.get(opts, :property_id))
    |> filter_lead(Keyword.get(opts, :lead_id))
    |> order_by([v], asc: v.starts_at, asc: v.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc "Lists the upcoming scheduled or confirmed visits of an owned property."
  @spec list_pending_visits(Scope.t(), integer()) :: [Visit.t()]
  def list_pending_visits(scope, property_id) do
    scope
    |> list_visits(property_id: property_id, from: NaiveDateTime.local_now())
    |> Enum.filter(&(&1.status in Visit.pending_statuses()))
  end

  @doc "Fetches an owned visit."
  @spec fetch_visit(Scope.t(), term()) :: {:ok, Visit.t()} | {:error, :not_found}
  def fetch_visit(scope, id) do
    with {:ok, id} <- cast_id(id),
         %Visit{} = visit <- scope |> owned_visits() |> preload(^@preloads) |> Repo.get(id) do
      {:ok, visit}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Builds a changeset for the visit form."
  @spec change_visit(Visit.t(), map()) :: Ecto.Changeset.t()
  def change_visit(visit, attrs \\ %{}), do: Visit.changeset(visit, attrs)

  @doc """
  Schedules a visit for an owned interest. A lead who was new or contacted
  moves to "visit scheduled".
  """
  @spec create_visit(Scope.t(), term(), map()) ::
          {:ok, Visit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def create_visit(scope, interest_id, attrs) do
    with {:ok, interest} <- Leads.fetch_interest(scope, interest_id) do
      Repo.transact(fn -> insert_visit(interest, attrs) end)
    end
  end

  defp insert_visit(interest, attrs) do
    with {:ok, visit} <-
           %Visit{interest_id: interest.id} |> Visit.changeset(attrs) |> Repo.insert() do
      if interest.status in [:new, :contacted],
        do: interest |> Ecto.Changeset.change(status: :visit_scheduled) |> Repo.update!()

      {:ok, visit}
    end
  end

  @doc "Updates, reschedules or cancels an owned visit."
  @spec update_visit(Scope.t(), term(), map()) ::
          {:ok, Visit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_visit(scope, id, attrs) do
    with {:ok, visit} <- fetch_visit(scope, id) do
      visit |> Visit.changeset(attrs) |> Repo.update()
    end
  end

  defp filter_property(query, nil), do: query

  defp filter_property(query, property_id),
    do: where(query, [interest: i], i.property_id == ^property_id)

  defp filter_lead(query, nil), do: query
  defp filter_lead(query, lead_id), do: where(query, [interest: i], i.lead_id == ^lead_id)

  defp owned_visits(%Scope{user: %{id: owner_id}}) when is_integer(owner_id) do
    from v in Visit,
      join: i in Interest,
      as: :interest,
      on: i.id == v.interest_id,
      join: l in Lead,
      on: l.id == i.lead_id,
      where: l.owner_id == ^owner_id
  end

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
