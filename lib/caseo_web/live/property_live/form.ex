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
