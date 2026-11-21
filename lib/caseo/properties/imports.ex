defmodule Caseo.Properties.Imports do
  @moduledoc """
  Listing imports started from the browser extension. An import is reviewed
  in a preview and then either creates a draft property or links the listing
  to an existing property or room. Every query is scoped to the owner, so a
  repeated listing never reveals another account's records.
  """

  import Ecto.Query

  alias Caseo.Accounts.Scope
  alias Caseo.Properties.ListingImages
  alias Caseo.Properties.ListingImport
  alias Caseo.Properties.ListingParser
  alias Caseo.Properties.Property
  alias Caseo.Properties.Room
  alias Caseo.Repo

  @doc "Stores the listing data sent by the extension."
  @spec create(Scope.t(), map()) :: {:ok, ListingImport.t()} | {:error, Ecto.Changeset.t()}
  def create(%Scope{user: %{id: owner_id}}, params) do
    %ListingImport{owner_id: owner_id}
    |> ListingImport.changeset(params)
    |> Repo.insert()
  end

  @doc "Fetches one of the owner's pending imports."
  @spec fetch_pending(Scope.t(), term()) :: {:ok, ListingImport.t()} | {:error, :not_found}
  def fetch_pending(%Scope{user: %{id: owner_id}}, id) do
    with {:ok, id} <- Ecto.Type.cast(:id, id),
         %ListingImport{} = listing_import <-
           Repo.get_by(ListingImport, id: id, owner_id: owner_id, status: :pending) do
      {:ok, listing_import}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Property form params guessed from the listing."
  @spec preview_params(ListingImport.t()) :: map()
  def preview_params(%ListingImport{raw: raw, url: url}) do
    raw |> ListingParser.to_params() |> Map.put("source_url", url)
  end

  @doc "The owner's properties and rooms already linked to this listing."
  @spec matches(Scope.t(), ListingImport.t()) :: %{properties: [Property.t()], rooms: [Room.t()]}
  def matches(scope, %ListingImport{source: source, external_id: external_id}) do
    %{
      properties:
        Repo.all(
          from p in owned_properties(scope),
            where: p.listing_source == ^source and p.listing_external_id == ^external_id
        ),
      rooms:
        Repo.all(
          from r in owned_rooms(scope),
            where: r.listing_source == ^source and r.listing_external_id == ^external_id,
            preload: :property
        )
    }
  end

  @doc "The owner's active properties with their rooms, as link targets."
  @spec link_targets(Scope.t()) :: [Property.t()]
  def link_targets(scope) do
    Repo.all(
      from p in owned_properties(scope),
        where: is_nil(p.archived_at),
        order_by: [desc: p.id],
        preload: :rooms
    )
  end

  @doc """
  Creates a draft property from the reviewed params. The listing is linked
  unless the owner already has it on another property or room. Selected
  images are copied only when the owner confirms they may reuse them.
  """
  @spec confirm(Scope.t(), ListingImport.t(), map(), [String.t()]) ::
          {:ok, Property.t(), non_neg_integer()} | {:error, Ecto.Changeset.t()}
  def confirm(%Scope{user: %{id: owner_id}} = scope, listing_import, params, image_urls) do
    linked? = linked?(scope, listing_import)

    result =
      Repo.transact(fn ->
        changeset =
          %Property{owner_id: owner_id, status: :draft}
          |> Property.changeset(params)
          |> keep_source(listing_import)
          |> Ecto.Changeset.put_change(:area_m2, ListingParser.area(listing_import.raw))
          |> then(&if(linked?, do: &1, else: put_listing(&1, listing_import)))

        with {:ok, property} <- Repo.insert(changeset),
             {:ok, _} <- finish(listing_import, property.id) do
          {:ok, property}
        end
      end)

    with {:ok, property} <- result do
      urls = Enum.filter(image_urls, &ListingImport.image_url?(listing_import, &1))
      {:ok, property, ListingImages.copy(scope, property.id, urls)}
    end
  end

  @doc """
  Links the listing to an existing property (`"property:ID"`) or room
  (`"room:ID"`), moving it off any other of the owner's records.
  """
  @spec link(Scope.t(), ListingImport.t(), String.t()) ::
          {:ok, Property.t()} | {:error, :not_found}
  def link(scope, listing_import, "property:" <> id),
    do: link_to(scope, listing_import, :property, id)

  def link(scope, listing_import, "room:" <> id), do: link_to(scope, listing_import, :room, id)
  def link(_scope, _listing_import, _target), do: {:error, :not_found}

  @doc "Discards a pending import."
  @spec discard(ListingImport.t()) :: :ok
  def discard(listing_import) do
    listing_import |> Ecto.Changeset.change(status: :discarded) |> Repo.update!()
    :ok
  end

  defp link_to(scope, listing_import, kind, raw_id) do
    Repo.transact(fn ->
      with {:ok, id} <- cast_id(raw_id),
           {:ok, property} <- target_property(scope, kind, id) do
        unlink(scope, listing_import)

        property = apply_link(kind, property, id, listing_import)

        {:ok, _} = finish(listing_import, property.id)
        {:ok, property}
      end
    end)
  end

  defp apply_link(:property, property, _id, listing_import) do
    property
    |> Ecto.Changeset.change(identity(listing_import))
    |> Ecto.Changeset.change(source_url: property.source_url || listing_import.url)
    |> Repo.update!()
  end

  defp apply_link(:room, property, room_id, listing_import) do
    identity = Keyword.new(identity(listing_import))
    Repo.update_all(from(r in Room, where: r.id == ^room_id), set: identity)
    property
  end

  defp target_property(scope, :property, id) do
    case Repo.get(owned_properties(scope), id) do
      %Property{} = property -> {:ok, property}
      nil -> {:error, :not_found}
    end
  end

  defp target_property(scope, :room, id) do
    case Repo.one(from r in owned_rooms(scope), where: r.id == ^id, preload: :property) do
      %Room{property: property} -> {:ok, property}
      nil -> {:error, :not_found}
    end
  end

  defp unlink(scope, %ListingImport{source: source, external_id: external_id}) do
    clear = [listing_source: nil, listing_external_id: nil, listing_url: nil]
    match = [listing_source: source, listing_external_id: external_id]

    Repo.update_all(from(p in owned_properties(scope), where: ^match), set: clear)
    Repo.update_all(from(r in owned_rooms(scope), where: ^match), set: clear)
  end

  defp linked?(scope, listing_import) do
    %{properties: properties, rooms: rooms} = matches(scope, listing_import)
    properties != [] or rooms != []
  end

  # The origin link is always kept, even if the owner cleared it in the preview.
  defp keep_source(changeset, listing_import) do
    if Ecto.Changeset.get_field(changeset, :source_url),
      do: changeset,
      else: Ecto.Changeset.put_change(changeset, :source_url, listing_import.url)
  end

  defp put_listing(changeset, listing_import) do
    changeset
    |> Ecto.Changeset.change(identity(listing_import))
    |> Ecto.Changeset.unique_constraint([:owner_id, :listing_source, :listing_external_id])
  end

  defp identity(%ListingImport{source: source, external_id: external_id, url: url}),
    do: %{listing_source: source, listing_external_id: external_id, listing_url: url}

  defp finish(listing_import, property_id) do
    listing_import
    |> Ecto.Changeset.change(status: :confirmed, property_id: property_id)
    |> Repo.update()
  end

  defp owned_properties(%Scope{user: %{id: owner_id}}),
    do: from(p in Property, where: p.owner_id == ^owner_id)

  defp owned_rooms(%Scope{user: %{id: owner_id}}) do
    from r in Room, join: p in assoc(r, :property), where: p.owner_id == ^owner_id
  end

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) and id > 0 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
