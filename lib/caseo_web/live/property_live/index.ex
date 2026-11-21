defmodule CaseoWeb.PropertyLive.Index do
  use CaseoWeb, :live_view

  alias Caseo.Properties
  alias Caseo.Properties.Property

  @impl true
  def handle_params(params, _uri, socket) do
    status = if params["estado"] == "archivados", do: :archived, else: :active

    {:noreply,
     socket
     |> assign(page_title: "Inmuebles", status: status)
     |> load_properties()}
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    case Properties.archive_property(socket.assigns.current_scope, id) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Inmueble archivado.") |> load_properties()}

      {:error, :not_found} ->
        {:noreply, socket |> put_flash(:error, "Inmueble no disponible.") |> load_properties()}
    end
  end

  defp load_properties(socket) do
    properties = Properties.list_properties(socket.assigns.current_scope, socket.assigns.status)
    stream(socket, :properties, properties, reset: true)
  end
end
