defmodule CaseoWeb.PropertyLive.Gallery do
  use CaseoWeb, :live_view

  alias Caseo.Leads
  alias Caseo.Leads.Interest
  alias Caseo.Properties
  alias Caseo.Properties.Offer
  alias Caseo.Properties.Photos
  alias Caseo.Properties.Property
  alias Caseo.Properties.Room

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:photos, [])
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: Photos.file_size_limit()
     )}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    with {:ok, property} <- Properties.fetch_property(socket.assigns.current_scope, id),
         {:ok, room} <- gallery_room(property, params) do
      {:noreply,
       socket
       |> assign(property: property, room: room, page_title: (room || property).name)
       |> assign(interest_groups: interest_groups(socket.assigns.current_scope, property, room))
       |> stream(:rooms, property.rooms, reset: true)
       |> load_photos()}
    else
      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Inmueble o habitación no disponible.")
         |> redirect(to: ~p"/inmuebles")}
    end
  end

  @impl true
  def handle_event("validate_photo", _params, socket), do: {:noreply, socket}

  def handle_event("upload_photo", _params, socket) do
    result =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
        {:ok,
         File.read(path)
         |> case do
           {:ok, data} -> Photos.add(scope(socket), property_id(socket), room_id(socket), data)
           {:error, _reason} -> {:error, :invalid_image}
         end}
      end)

    case result do
      [outcome] -> photo_result(socket, outcome, "Foto guardada.")
      [] -> {:noreply, socket}
    end
  end

  def handle_event("cancel_photo", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("cover_photo", %{"id" => id}, socket) do
    result = Photos.set_cover(scope(socket), property_id(socket), room_id(socket), id)
    photo_result(socket, result, "Portada actualizada.")
  end

  def handle_event("delete_photo", %{"id" => id}, socket) do
    result = Photos.delete(scope(socket), property_id(socket), room_id(socket), id)
    photo_result(socket, result, "Foto eliminada.")
  end

  attr :offer, :map, required: true

  defp availability(assigns) do
    ~H"""
    <div class="workspace-muted space-y-1 text-sm">
      <p>
        <%= if @offer.available_on do %>
          Disponible desde {Calendar.strftime(@offer.available_on, "%d/%m/%Y")}
        <% else %>
          Disponibilidad por confirmar
        <% end %>
        <span :if={@offer.available_until}>
          hasta {Calendar.strftime(@offer.available_until, "%d/%m/%Y")}
        </span>
      </p>
      <p :if={@offer.rental_term == :temporary}>Alquiler temporal</p>
      <p :if={@offer.minimum_months}>Estancia mínima de {@offer.minimum_months} meses</p>
      <p :if={@offer.maximum_months}>Estancia máxima de {@offer.maximum_months} meses</p>
      <p :if={@offer.for_students}>
        Para estudiantes <span :if={@offer.academic_year}>· Curso {@offer.academic_year}</span>
      </p>
    </div>
    """
  end

  # Interests grouped by status, in pipeline order. A room shows only its own.
  defp interest_groups(scope, property, room) do
    interests =
      scope
      |> Leads.list_property_interests(property.id)
      |> Enum.filter(&(is_nil(room) || &1.room_id == room.id))
      |> Enum.group_by(& &1.status)

    for {label, status} <- Interest.status_options(), Map.has_key?(interests, status) do
      {status, label, interests[status]}
    end
  end

  defp gallery_room(%Property{mode: :rooms, rooms: rooms}, %{"room_id" => id}) do
    case Enum.find(rooms, &(to_string(&1.id) == id)) do
      %Room{} = room -> {:ok, room}
      nil -> {:error, :not_found}
    end
  end

  defp gallery_room(_property, %{"room_id" => _id}), do: {:error, :not_found}
  defp gallery_room(_property, _params), do: {:ok, nil}

  defp photo_result(socket, {:ok, _}, message) do
    {:noreply, socket |> put_flash(:info, message) |> load_photos()}
  end

  defp photo_result(socket, {:error, reason}, _message) do
    message =
      case reason do
        :invalid_image -> "Selecciona una imagen JPEG, PNG o WebP de hasta 5 MB."
        :gallery_full -> "La galería ya tiene #{Photos.image_limit()} fotos."
        _ -> "No se pudo guardar el cambio en la galería."
      end

    {:noreply, socket |> put_flash(:error, message) |> load_photos()}
  end

  defp load_photos(socket) do
    photos = Photos.list(scope(socket), property_id(socket), room_id(socket))
    cover = List.first(photos)

    socket
    |> assign(cover_id: cover && cover.id, gallery_full?: length(photos) >= Photos.image_limit())
    |> stream(:photos, photos, reset: true)
  end

  defp scope(socket), do: socket.assigns.current_scope
  defp property_id(socket), do: socket.assigns.property.id
  defp room_id(%{assigns: %{room: nil}}), do: nil
  defp room_id(%{assigns: %{room: room}}), do: room.id

  defp upload_error_label(:too_large), do: "La foto supera los 5 MB."
  defp upload_error_label(:not_accepted), do: "Selecciona una foto JPEG, PNG o WebP."
  defp upload_error_label(:too_many_files), do: "Selecciona una foto cada vez."
  defp upload_error_label(_), do: "No se pudo cargar la foto."
end
