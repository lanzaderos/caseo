defmodule Caseo.Properties do
  @moduledoc """
  Manages rental properties within the authenticated owner's scope.

  Owner-facing access to applications, tenant records and attachments must also
  verify that the record belongs to a property in this scope. Public submission
  and upload links authorize only the operation and record bound to the link.
  """

  import Ecto.Query

  alias Caseo.Accounts.Scope
  alias Caseo.Properties.Property
  alias Caseo.Repo

  @doc "Lists the owner's active or archived properties."
  @spec list_properties(Scope.t(), :active | :archived) :: [Property.t()]
  def list_properties(scope, status \\ :active) do
    scope
    |> owned_properties()
    |> with_status(status)
    |> order_by([p], desc: p.id)
    |> Repo.all()
  end

  @doc "Fetches an owned property, including archived properties."
  @spec fetch_property(Scope.t(), term()) :: {:ok, Property.t()} | {:error, :not_found}
  def fetch_property(scope, id) do
    with {:ok, id} <- cast_id(id),
         %Property{} = property <- Repo.get(owned_properties(scope), id) do
      {:ok, property}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Builds a changeset for the property form."
  @spec change_property(Property.t(), map()) :: Ecto.Changeset.t()
  def change_property(property, attrs \\ %{}), do: Property.changeset(property, attrs)

  @doc "Creates a property owned by the caller."
  @spec create_property(Scope.t(), map()) :: {:ok, Property.t()} | {:error, Ecto.Changeset.t()}
  def create_property(%Scope{user: %{id: owner_id}}, attrs) do
    %Property{owner_id: owner_id}
    |> change_property(attrs)
    |> Repo.insert()
  end

  @doc "Updates the editable fields of a property owned by the caller."
  @spec update_property(Scope.t(), term(), map()) ::
          {:ok, Property.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_property(scope, id, attrs) do
    with {:ok, property} <- fetch_property(scope, id) do
      property |> change_property(attrs) |> Repo.update()
    end
  end

  @doc "Archives an active property using a single owner-scoped write."
  @spec archive_property(Scope.t(), term()) :: :ok | {:error, :not_found}
  def archive_property(scope, id) do
    with {:ok, id} <- cast_id(id) do
      now = DateTime.utc_now(:second)

      query =
        scope
        |> owned_properties()
        |> with_status(:active)
        |> where([p], p.id == ^id)

      case Repo.update_all(query, set: [archived_at: now, updated_at: now]) do
        {1, _} -> :ok
        {0, _} -> {:error, :not_found}
      end
    end
  end

  defp owned_properties(%Scope{user: %{id: owner_id}}) when is_integer(owner_id) do
    from p in Property, where: p.owner_id == ^owner_id
  end

  defp with_status(query, :active), do: where(query, [p], is_nil(p.archived_at))
  defp with_status(query, :archived), do: where(query, [p], not is_nil(p.archived_at))

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
