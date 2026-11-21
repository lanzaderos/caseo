defmodule CaseoWeb.LeadLive.Index do
  use CaseoWeb, :live_view

  alias Caseo.Leads
  alias Caseo.Leads.Interest
  alias Caseo.Leads.Lead

  @impl true
  def mount(_params, _session, socket) do
    leads = Leads.list_leads(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(page_title: "Interesados", form: to_form(Leads.change_lead(%Lead{})))
     |> stream(:leads, leads)}
  end

  @impl true
  def handle_event("validate", %{"lead" => params}, socket) do
    form = %Lead{} |> Leads.change_lead(params) |> to_form(action: :validate)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"lead" => params}, socket) do
    case Leads.create_lead(socket.assigns.current_scope, params) do
      {:ok, lead} ->
        {:noreply,
         socket
         |> put_flash(:info, "Interesado creado.")
         |> push_navigate(to: ~p"/interesados/#{lead.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp interest_summary(interests) do
    Enum.map_join(interests, ", ", fn interest ->
      place =
        if interest.room,
          do: "#{interest.property.name} · #{interest.room.name}",
          else: interest.property.name

      "#{place} (#{Interest.status_label(interest.status)})"
    end)
  end
end
