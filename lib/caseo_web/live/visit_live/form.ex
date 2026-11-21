defmodule CaseoWeb.VisitLive.Form do
  use CaseoWeb, :live_view

  alias Caseo.Leads
  alias Caseo.Visits
  alias Caseo.Visits.Visit

  @impl true
  def mount(params, _session, socket) do
    case load(socket.assigns.live_action, params, socket.assigns.current_scope) do
      {:ok, visit, interest} ->
        {:ok,
         assign(socket,
           page_title: if(visit.id, do: "Visita", else: "Agendar visita"),
           visit: visit,
           interest: interest,
           form: to_form(Visits.change_visit(visit)),
           slots: if(visit.id, do: [], else: Visits.free_slots(socket.assigns.current_scope))
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Visita no disponible.")
         |> push_navigate(to: ~p"/visitas")}
    end
  end

  defp load(:new, params, scope) do
    with {:ok, interest} <- Leads.fetch_interest(scope, params["interes"]) do
      {:ok, %Visit{interest_id: interest.id}, interest}
    end
  end

  defp load(:edit, %{"id" => id}, scope) do
    with {:ok, visit} <- Visits.fetch_visit(scope, id), do: {:ok, visit, visit.interest}
  end

  @impl true
  def handle_event("validate", %{"visit" => params}, socket) do
    form = socket.assigns.visit |> Visits.change_visit(params) |> to_form(action: :validate)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"visit" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      if socket.assigns.visit.id,
        do: Visits.update_visit(scope, socket.assigns.visit.id, params),
        else: Visits.create_visit(scope, socket.assigns.interest.id, params)

    case result do
      {:ok, visit} ->
        {:noreply,
         socket
         |> put_flash(:info, "Visita guardada.")
         |> push_navigate(to: ~p"/visitas/#{visit.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :not_found} ->
        {:noreply, push_navigate(socket, to: ~p"/visitas")}
    end
  end

  # Fills the form with one of the owner's free slots.
  def handle_event("pick_slot", %{"slot" => slot, "minutes" => minutes}, socket) do
    params =
      Map.merge(socket.assigns.form.params, %{
        "starts_at" => String.slice(slot, 0, 16),
        "duration_minutes" => minutes
      })

    form = socket.assigns.visit |> Visits.change_visit(params) |> to_form()
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("cancel_visit", _params, socket) do
    update_status(socket, :cancelled, "Visita cancelada.")
  end

  def handle_event("approve", _params, socket) do
    update_status(socket, :confirmed, "Visita aprobada.")
  end

  def handle_event("reject", _params, socket) do
    update_status(socket, :cancelled, "Solicitud rechazada.")
  end

  def handle_event("mark_visited", _params, socket) do
    scope = socket.assigns.current_scope

    case Leads.update_interest(scope, socket.assigns.interest.id, %{"status" => "visited"}) do
      {:ok, interest} ->
        {:noreply,
         socket
         |> assign(interest: %{socket.assigns.interest | status: interest.status})
         |> put_flash(:info, "Interesado marcado como visitado.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo actualizar el interesado.")}
    end
  end

  defp update_status(socket, status, message) do
    case Visits.update_visit(socket.assigns.current_scope, socket.assigns.visit.id, %{
           "status" => status
         }) do
      {:ok, _visit} ->
        {:noreply, socket |> put_flash(:info, message) |> push_navigate(to: ~p"/visitas")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo actualizar la visita.")}
    end
  end

  # After a visit, offer to move a lead still earlier in the pipeline.
  defp suggest_visited?(visit, interest),
    do: visit.status == :done and interest.status in [:new, :contacted, :visit_scheduled]

  defp place(%{room: nil, property: property}), do: property.name
  defp place(%{room: room, property: property}), do: "#{property.name} · #{room.name}"

  defp format_time(iso) do
    case NaiveDateTime.from_iso8601(iso) do
      {:ok, time} -> Calendar.strftime(time, "%d/%m/%Y %H:%M")
      _ -> iso
    end
  end
end
