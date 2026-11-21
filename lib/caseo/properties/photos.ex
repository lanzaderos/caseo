defmodule Caseo.Properties.Photos do
  @moduledoc "Stores and serves galleries through the authenticated owner's scope."

  import Ecto.Query

  alias Caseo.Accounts.Scope
  alias Caseo.Properties.Photo
  alias Caseo.Properties.Property
  alias Caseo.Properties.Room
  alias Caseo.Repo

  @image_limit 12
  @file_size_limit 5 * 1024 * 1024

  def image_limit, do: @image_limit
  def file_size_limit, do: @file_size_limit

  def list(scope, property_id, room_id) do
    scope
    |> gallery(property_id, room_id)
    |> order_by([photo], desc: photo.cover, asc: photo.id)
    |> Repo.all()
  end

  def fetch(scope, raw_id) do
    with {:ok, id} <- cast_id(raw_id),
         %Photo{} = photo <-
           scope
           |> owned_photos()
           |> where([photo], photo.id == ^id)
           |> select_merge([photo], %{data: photo.data})
           |> Repo.one() do
      {:ok, photo}
    else
      _ -> {:error, :not_found}
    end
  end

  def add(scope, property_id, room_id, data)
      when is_binary(data) and byte_size(data) <= @file_size_limit do
    with {:ok, content_type} <- image_type(data) do
      with_gallery(scope, property_id, room_id, fn query ->
        insert_photo(query, %Photo{
          property_id: property_id,
          room_id: room_id,
          content_type: content_type,
          data: data
        })
      end)
    end
  end

  def add(_scope, _property_id, _room_id, _data), do: {:error, :invalid_image}

  def set_cover(scope, property_id, room_id, raw_id) do
    with {:ok, id} <- cast_id(raw_id) do
      with_gallery(scope, property_id, room_id, fn query ->
        replace_cover(query, id)
      end)
    end
  end

  def delete(scope, property_id, room_id, raw_id) do
    with {:ok, id} <- cast_id(raw_id) do
      with_gallery(scope, property_id, room_id, fn query ->
        delete_photo(query, id)
      end)
    end
  end

  defp insert_photo(query, photo) do
    count = Repo.aggregate(query, :count)

    if count < @image_limit do
      Repo.insert(%{photo | cover: count == 0})
    else
      {:error, :gallery_full}
    end
  end

  defp replace_cover(query, id) do
    selected = where(query, [photo], photo.id == ^id)

    if Repo.exists?(selected) do
      query |> where([photo], photo.cover) |> Repo.update_all(set: [cover: false])
      Repo.update_all(selected, set: [cover: true])
      {:ok, :saved}
    else
      {:error, :not_found}
    end
  end

  defp delete_photo(query, id) do
    case query |> where([photo], photo.id == ^id) |> Repo.delete_all() do
      {1, _} -> {:ok, :deleted}
      {0, _} -> {:error, :not_found}
    end
  end

  defp with_gallery(%Scope{user: %{id: owner_id}} = scope, property_id, room_id, operation) do
    Repo.transact(fn ->
      property =
        Repo.one(
          from p in Property,
            where: p.id == ^property_id and p.owner_id == ^owner_id,
            lock: "FOR UPDATE"
        )

      if gallery_available?(property, room_id) do
        operation.(gallery(scope, property_id, room_id))
      else
        {:error, :not_found}
      end
    end)
  end

  defp gallery_available?(%Property{}, nil), do: true

  defp gallery_available?(%Property{id: id, mode: :rooms}, room_id) do
    Repo.exists?(from r in Room, where: r.id == ^room_id and r.property_id == ^id)
  end

  defp gallery_available?(_property, _room_id), do: false

  defp gallery(scope, property_id, room_id) do
    query = where(owned_photos(scope), [photo], photo.property_id == ^property_id)

    case room_id do
      nil -> where(query, [photo], is_nil(photo.room_id))
      id -> where(query, [photo], photo.room_id == ^id)
    end
  end

  defp owned_photos(%Scope{user: %{id: owner_id}}) do
    from photo in Photo,
      join: property in assoc(photo, :property),
      where: property.owner_id == ^owner_id,
      where: is_nil(photo.room_id) or property.mode == :rooms
  end

  defp cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when id > 0 and id <= 9_223_372_036_854_775_807 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp image_type(<<137, "PNG", 13, 10, 26, 10, _size::32, "IHDR", _rest::binary>>),
    do: {:ok, "image/png"}

  defp image_type(<<255, 216, 255, _rest::binary>>), do: {:ok, "image/jpeg"}

  defp image_type(<<"RIFF", _size::32, "WEBP", _rest::binary>>), do: {:ok, "image/webp"}

  defp image_type(_data), do: {:error, :invalid_image}
end
