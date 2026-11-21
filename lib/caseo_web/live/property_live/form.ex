defmodule CaseoWeb.PropertyLive.Form do
  use CaseoWeb, :live_view

  alias Caseo.Properties
  alias Caseo.Properties.Imports
  alias Caseo.Properties.ListingImport
  alias Caseo.Properties.Property

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    {:noreply, load_form(socket, %Property{}, "Nuevo inmueble")}
  end

  def handle_params(%{"import_id" => id}, _uri, %{assigns: %{live_action: :import}} = socket) do
    scope = socket.assigns.current_scope

    case Imports.fetch_pending(scope, id) do
      {:ok, listing_import} ->
        params = Imports.preview_params(listing_import)
        changeset = Properties.change_property(%Property{}, params)
        images = ListingImport.image_urls(listing_import)

        {:noreply,
         socket
         |> load_form(%Property{}, "Revisar anuncio importado")
         |> assign(
           form: to_form(changeset, action: :validate),
           listing_import: listing_import,
           matches: Imports.matches(scope, listing_import),
           link_targets: Imports.link_targets(scope),
           images: images,
           selected_images: images,
           reuse_authorized: false,
           images_error: nil
         )}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Importación no disponible. Vuelve a importar el anuncio.")
         |> redirect(to: ~p"/inmuebles")}
    end
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    case Properties.fetch_property(socket.assigns.current_scope, id) do
      {:ok, property} -> {:noreply, load_form(socket, property, "Editar inmueble")}
      {:error, :not_found} -> {:noreply, unavailable(socket)}
    end
  end

  @impl true
  def handle_event("validate", %{"property" => attrs} = params, socket) do
    changeset = Properties.change_property(socket.assigns.property, attrs)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign_image_choice(params)}
  end

  def handle_event(
        "save",
        %{"property" => attrs} = params,
        %{assigns: %{live_action: :import}} = socket
      ) do
    socket = assign_image_choice(socket, params)
    %{selected_images: images, reuse_authorized: authorized?} = socket.assigns

    if images != [] and not authorized? do
      # Show the form errors too, so the owner fixes everything in one go.
      changeset = Properties.change_property(%Property{}, attrs)

      {:noreply,
       socket
       |> assign(:form, to_form(changeset, action: :insert))
       |> assign(:images_error, "Confirma que puedes reutilizar las fotos o desmárcalas.")}
    else
      scope = socket.assigns.current_scope

      case Imports.confirm(scope, socket.assigns.listing_import, attrs, images) do
        {:ok, property, copied} ->
          {:noreply,
           socket
           |> put_flash(:info, "Borrador creado#{photos_copied(copied)}.")
           |> push_navigate(to: ~p"/inmuebles/#{property.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  def handle_event("save", %{"property" => attrs}, socket) do
    case save_property(socket, attrs) do
      {:ok, property} ->
        {:noreply,
         socket
         |> put_flash(:info, "Inmueble guardado.")
         |> push_navigate(to: return_path(property))}

      {:error, :not_found} ->
        {:noreply, unavailable(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("link", %{"target" => target}, %{assigns: %{live_action: :import}} = socket) do
    case Imports.link(socket.assigns.current_scope, socket.assigns.listing_import, target) do
      {:ok, property} ->
        {:noreply,
         socket
         |> put_flash(:info, "Anuncio vinculado a «#{property.name}».")
         |> push_navigate(to: ~p"/inmuebles/#{property.id}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Elige un inmueble o una habitación.")}
    end
  end

  def handle_event("discard", _params, %{assigns: %{live_action: :import}} = socket) do
    :ok = Imports.discard(socket.assigns.listing_import)

    {:noreply,
     socket
     |> put_flash(:info, "Importación descartada.")
     |> push_navigate(to: ~p"/inmuebles")}
  end

  defp assign_image_choice(%{assigns: %{live_action: :import}} = socket, params) do
    selected = Enum.filter(socket.assigns.images, &(&1 in List.wrap(params["images"])))

    assign(socket,
      selected_images: selected,
      reuse_authorized: params["reuse_authorized"] == "true",
      images_error: nil
    )
  end

  defp assign_image_choice(socket, _params), do: socket

  defp photos_copied(0), do: ""
  defp photos_copied(1), do: " con 1 foto"
  defp photos_copied(count), do: " con #{count} fotos"

  attr :form, Phoenix.HTML.Form, required: true

  defp rental_fields(assigns) do
    ~H"""
    <.input
      field={@form[:rent]}
      label="Renta mensual (€)"
      inputmode="decimal"
      placeholder="850,00"
      required
    />
    <.input
      field={@form[:rental_term]}
      type="select"
      label="Duración del alquiler"
      options={[
        {"Por confirmar", ""},
        {"Larga duración", :long_term},
        {"Temporal", :temporary}
      ]}
    />
    <.input
      field={@form[:available_on]}
      type="date"
      label="Disponible desde"
      required={@form[:rental_term].value in [:temporary, "temporary"]}
    />
    <%= if @form[:rental_term].value in [:temporary, "temporary"] do %>
      <.input field={@form[:available_until]} type="date" label="Disponible hasta" />
      <.input
        field={@form[:minimum_months]}
        type="number"
        min="1"
        label="Estancia mínima (meses)"
      />
      <.input
        field={@form[:maximum_months]}
        type="number"
        min="1"
        label="Estancia máxima (meses)"
      />
    <% end %>
    <div class="sm:col-span-2">
      <.input field={@form[:for_students]} type="checkbox" label="Orientado a estudiantes" />
    </div>
    <.input
      :if={Phoenix.HTML.Form.normalize_value("checkbox", @form[:for_students].value)}
      field={@form[:academic_year]}
      label="Curso académico (opcional)"
      placeholder="2026–2027"
      maxlength="100"
    />
    """
  end

  defp address_errors?(form) do
    form.source.action in [:insert, :update] &&
      Enum.any?(
        [:street, :municipality, :postal_code, :province, :latitude, :longitude],
        fn field ->
          form[field].errors != []
        end
      )
  end

  defp load_form(socket, property, title) do
    assign(socket,
      page_title: title,
      property: property,
      return_path: return_path(property),
      form: to_form(Properties.change_property(property))
    )
  end

  defp save_property(%{assigns: %{live_action: :new, current_scope: scope}}, attrs) do
    Properties.create_property(scope, attrs)
  end

  defp save_property(socket, attrs) do
    Properties.update_property(socket.assigns.current_scope, socket.assigns.property.id, attrs)
  end

  defp return_path(%Property{archived_at: nil}), do: ~p"/inmuebles"
  defp return_path(%Property{}), do: ~p"/inmuebles?estado=archivados"

  defp unavailable(socket) do
    socket
    |> put_flash(:error, "Inmueble no disponible.")
    |> redirect(to: ~p"/inmuebles")
  end
end
