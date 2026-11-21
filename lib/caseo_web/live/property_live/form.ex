defmodule CaseoWeb.PropertyLive.Form do
  use CaseoWeb, :live_view

  alias Caseo.Properties
  alias Caseo.Properties.Property

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    {:noreply, load_form(socket, %Property{}, "Nuevo inmueble")}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    case Properties.fetch_property(socket.assigns.current_scope, id) do
      {:ok, property} -> {:noreply, load_form(socket, property, "Editar inmueble")}
      {:error, :not_found} -> {:noreply, unavailable(socket)}
    end
  end

  @impl true
  def handle_event("validate", %{"property" => attrs}, socket) do
    changeset = Properties.change_property(socket.assigns.property, attrs)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
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
