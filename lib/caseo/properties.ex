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
  alias Caseo.Properties.Room
  alias Caseo.Repo

  @doc "Lists the owner's active or archived properties."
  @spec list_properties(Scope.t(), :active | :archived) :: [Property.t()]
  def list_properties(scope, status \\ :active) do
    scope
    |> owned_properties()
    |> with_status(status)
    |> order_by([p], desc: p.id)
    |> Repo.all()
    |> Repo.preload(:rooms)
  end

  @doc "Fetches an owned property, including archived properties."
  @spec fetch_property(Scope.t(), term()) :: {:ok, Property.t()} | {:error, :not_found}
  def fetch_property(scope, id) do
    with {:ok, id} <- cast_id(id),
         %Property{} = property <- Repo.get(owned_properties(scope), id) do
      {:ok, Repo.preload(property, :rooms)}
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
    case cast_id(id) do
      {:ok, id} -> Repo.transact(fn -> update_owned_property(scope, id, attrs) end)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp update_owned_property(scope, id, attrs) do
    query = scope |> owned_properties() |> lock("FOR UPDATE")

    case Repo.get(query, id) do
      %Property{} = property ->
        property |> Repo.preload(:rooms) |> change_property(attrs) |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Marks an owned draft property as ready."
  @spec mark_ready(Scope.t(), term()) :: :ok | {:error, :not_found}
  def mark_ready(scope, id) do
    with {:ok, id} <- cast_id(id) do
      query = from p in owned_properties(scope), where: p.id == ^id and p.status == :draft

      case Repo.update_all(query, set: [status: :ready, updated_at: DateTime.utc_now(:second)]) do
        {1, _} -> :ok
        {0, _} -> {:error, :not_found}
      end
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

  @idealista_link ~r"https?://(?:www\.|m\.)?idealista\.com/(?:[a-z]{2}/)?inmueble/([0-9]{1,20})"

  @doc """
  Finds the owner's active property, or room, imported from an Idealista
  listing linked in `text` (e.g. a lead's WhatsApp message).
  """
  @spec find_linked_listing(Scope.t(), String.t()) :: {Property.t(), Room.t() | nil} | nil
  def find_linked_listing(scope, text) when is_binary(text) do
    case @idealista_link |> Regex.scan(text, capture: :all_but_first) |> List.flatten() do
      [] -> nil
      ids -> find_listing(scope, Enum.uniq(ids))
    end
  end

  def find_linked_listing(_scope, _text), do: nil

  defp find_listing(scope, ids) do
    listed = fn query ->
      where(query, [x], x.listing_source == "idealista" and x.listing_external_id in ^ids)
    end

    properties = scope |> owned_properties() |> with_status(:active)

    case properties |> listed.() |> limit(1) |> Repo.one() do
      %Property{} = property ->
        {Repo.preload(property, :rooms), nil}

      nil ->
        query =
          from r in listed.(Room),
            join: p in subquery(properties),
            on: p.id == r.property_id,
            limit: 1,
            select: {p, r}

        case Repo.one(query) do
          {property, room} -> {Repo.preload(property, :rooms), room}
          nil -> nil
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
