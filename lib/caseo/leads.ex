defmodule Caseo.Leads do
  @moduledoc """
  Manages the owner's leads and their interest in each property or room.

  Every read and write is scoped to the caller: a lead belongs to one owner, and
  an interest may only link that owner's lead to that owner's property.
  """

  import Ecto.Query

  alias Caseo.Accounts.Scope
  alias Caseo.Leads.Interest
  alias Caseo.Leads.Lead
  alias Caseo.Properties
  alias Caseo.Repo

  @doc "Lists the owner's leads, newest first, with their interests."
  @spec list_leads(Scope.t()) :: [Lead.t()]
  def list_leads(scope) do
    scope
    |> owned_leads()
    |> order_by([l], desc: l.id)
    |> Repo.all()
    |> Repo.preload(interests: [:property, :room])
  end

  @doc "Fetches an owned lead with its interests."
  @spec fetch_lead(Scope.t(), term()) :: {:ok, Lead.t()} | {:error, :not_found}
  def fetch_lead(scope, id) do
    with {:ok, id} <- cast_id(id),
         %Lead{} = lead <- Repo.get(owned_leads(scope), id) do
      {:ok, Repo.preload(lead, interests: [:property, :room])}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Builds a changeset for the lead form."
  @spec change_lead(Lead.t(), map()) :: Ecto.Changeset.t()
  def change_lead(lead, attrs \\ %{}), do: Lead.changeset(lead, attrs)

  @doc "Creates a lead owned by the caller. A phone number is unique per owner."
  @spec create_lead(Scope.t(), map()) :: {:ok, Lead.t()} | {:error, Ecto.Changeset.t()}
  def create_lead(%Scope{user: %{id: owner_id}}, attrs) do
    %Lead{owner_id: owner_id} |> Lead.changeset(attrs) |> Repo.insert()
  end

  @doc "Updates an owned lead."
  @spec update_lead(Scope.t(), term(), map()) ::
          {:ok, Lead.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_lead(scope, id, attrs) do
    with {:ok, lead} <- fetch_lead(scope, id) do
      lead |> Lead.changeset(attrs) |> Repo.update()
    end
  end

  @doc "Deletes an owned lead together with its interests."
  @spec delete_lead(Scope.t(), term()) :: :ok | {:error, :not_found}
  def delete_lead(scope, id) do
    with {:ok, id} <- cast_id(id) do
      case Repo.delete_all(where(owned_leads(scope), [l], l.id == ^id)) do
        {1, _} -> :ok
        {0, _} -> {:error, :not_found}
      end
    end
  end

  @doc """
  Links an owned lead to an owned property, or to one of its rooms when
  `room_id` is given.
  """
  @spec add_interest(Scope.t(), term(), term(), term()) ::
          {:ok, Interest.t()} | {:error, :not_found | :already_linked}
  def add_interest(scope, lead_id, property_id, room_id \\ nil) do
    with {:ok, lead} <- fetch_lead(scope, lead_id),
         {:ok, property} <- Properties.fetch_property(scope, property_id),
         {:ok, room_id} <- property_room_id(property, room_id) do
      %Interest{lead_id: lead.id, property_id: property.id, room_id: room_id}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint([:lead_id, :property_id, :room_id])
      |> Repo.insert()
      |> case do
        {:ok, interest} -> {:ok, interest}
        {:error, _changeset} -> {:error, :already_linked}
      end
    end
  end

  @doc "Builds a changeset for an interest's status form."
  @spec change_interest(Interest.t(), map()) :: Ecto.Changeset.t()
  def change_interest(interest, attrs \\ %{}), do: Interest.status_changeset(interest, attrs)

  @doc "Fetches an owned interest with its lead, property and room."
  @spec fetch_interest(Scope.t(), term()) :: {:ok, Interest.t()} | {:error, :not_found}
  def fetch_interest(scope, id) do
    with {:ok, id} <- cast_id(id),
         %Interest{} = interest <- Repo.get(owned_interests(scope), id) do
      {:ok, Repo.preload(interest, [:lead, :property, :room])}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Changes the status of an owned interest."
  @spec update_interest(Scope.t(), term(), map()) ::
          {:ok, Interest.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_interest(scope, id, attrs) do
    with {:ok, id} <- cast_id(id),
         %Interest{} = interest <- Repo.get(owned_interests(scope), id) do
      interest |> Interest.status_changeset(attrs) |> Repo.update()
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Unlinks a lead from a property or room."
  @spec delete_interest(Scope.t(), term()) :: :ok | {:error, :not_found}
  def delete_interest(scope, id) do
    with {:ok, id} <- cast_id(id) do
      case Repo.delete_all(where(owned_interests(scope), [i], i.id == ^id)) do
        {1, _} -> :ok
        {0, _} -> {:error, :not_found}
      end
    end
  end

  @doc "Lists the interests in an owned property, with their lead and room."
  @spec list_property_interests(Scope.t(), integer()) :: [Interest.t()]
  def list_property_interests(scope, property_id) do
    scope
    |> owned_interests()
    |> where([i], i.property_id == ^property_id)
    |> order_by([i], asc: i.id)
    |> preload([:lead, :property, :room])
    |> Repo.all()
  end

  @doc "Counts the leads still in play (not discarded) for each owned property."
  @spec count_by_property(Scope.t()) :: %{integer() => non_neg_integer()}
  def count_by_property(scope) do
    scope
    |> owned_interests()
    |> where([i], i.status != :discarded)
    |> group_by([i], i.property_id)
    |> select([i], {i.property_id, count(i.lead_id, :distinct)})
    |> Repo.all()
    |> Map.new()
  end

  defp property_room_id(_property, room_id) when room_id in [nil, ""], do: {:ok, nil}

  defp property_room_id(property, room_id) do
    with {:ok, room_id} <- cast_id(room_id),
         true <- Enum.any?(property.rooms, &(&1.id == room_id)) do
      {:ok, room_id}
    else
      _ -> {:error, :not_found}
    end
  end

  defp owned_leads(%Scope{user: %{id: owner_id}}) when is_integer(owner_id) do
    from l in Lead, where: l.owner_id == ^owner_id
  end

  defp owned_interests(%Scope{user: %{id: owner_id}}) when is_integer(owner_id) do
    from i in Interest,
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
