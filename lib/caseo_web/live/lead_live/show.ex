defmodule CaseoWeb.LeadLive.Show do
  use CaseoWeb, :live_view

  alias Caseo.Leads
  alias Caseo.Leads.Interest
  alias Caseo.Leads.Lead
  alias Caseo.Properties
  alias Caseo.Visits
  alias Caseo.Whatsapp
  alias Caseo.Whatsapp.Account

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Leads.fetch_lead(socket.assigns.current_scope, id) do
      {:ok, lead} ->
        {:ok,
         socket
         |> assign(
           lead: lead,
           page_title: lead.name,
           form: to_form(Leads.change_lead(lead)),
           link_form: to_form(%{"target" => ""}, as: :link),
           target_options: target_options(socket.assigns.current_scope),
           visits: Visits.list_visits(socket.assigns.current_scope, lead_id: lead.id),
           schedule: nil,
           whatsapp_linked: false
         )
         |> stream(:interests, Enum.map(lead.interests, &interest_item/1))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Interesado no disponible.")
         |> push_navigate(to: ~p"/interesados")}
    end
  end

  @impl true
  def handle_event("validate", %{"lead" => params}, socket) do
    form = socket.assigns.lead |> Leads.change_lead(params) |> to_form(action: :validate)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"lead" => params}, socket) do
    case Leads.update_lead(scope(socket), socket.assigns.lead.id, params) do
      {:ok, lead} ->
        {:noreply,
         socket
         |> assign(lead: lead, page_title: lead.name, form: to_form(Leads.change_lead(lead)))
         |> put_flash(:info, "Interesado guardado.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :not_found} ->
        {:noreply, push_navigate(socket, to: ~p"/interesados")}
    end
  end

  def handle_event("delete", _params, socket) do
    Leads.delete_lead(scope(socket), socket.assigns.lead.id)

    {:noreply,
     socket
     |> put_flash(:info, "Interesado eliminado.")
     |> push_navigate(to: ~p"/interesados")}
  end

  def handle_event("link", %{"link" => %{"target" => target}}, socket) do
    {property_id, room_id} = parse_target(target)

    case Leads.add_interest(scope(socket), socket.assigns.lead.id, property_id, room_id) do
      {:ok, _interest} ->
        {:noreply,
         socket
         |> reload_lead()
         |> assign(link_form: to_form(%{"target" => ""}, as: :link))
         |> put_flash(:info, "Inmueble vinculado.")}

      {:error, :already_linked} ->
        {:noreply, put_flash(socket, :error, "Ya está vinculado a ese inmueble.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Elige un inmueble.")}
    end
  end

  def handle_event("validate_interest", %{"interest_id" => id, "interest" => params}, socket) do
    case find_interest(socket, id) do
      %Interest{} = interest ->
        changeset = Leads.change_interest(interest, params)
        {:noreply, stream_insert(socket, :interests, interest_item(interest, changeset))}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("save_interest", %{"interest_id" => id, "interest" => params}, socket) do
    case Leads.update_interest(scope(socket), id, params) do
      {:ok, _interest} ->
        {:noreply, socket |> reload_lead() |> put_flash(:info, "Estado actualizado.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        interest = find_interest(socket, id)
        {:noreply, stream_insert(socket, :interests, interest_item(interest, changeset))}

      {:error, :not_found} ->
        {:noreply, reload_lead(socket)}
    end
  end

  def handle_event("open_schedule", %{"id" => id}, socket) do
    case find_interest(socket, id) do
      %Interest{} = interest ->
        {:noreply,
         assign(socket,
           schedule: interest,
           whatsapp_linked: Account.linked?(Whatsapp.get_account(scope(socket)))
         )}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("close_schedule", _params, socket) do
    {:noreply, assign(socket, schedule: nil)}
  end

  def handle_event("unlink", %{"id" => id}, socket) do
    Leads.delete_interest(scope(socket), id)
    {:noreply, socket |> reload_lead() |> put_flash(:info, "Inmueble desvinculado.")}
  end

  defp reload_lead(socket) do
    case Leads.fetch_lead(scope(socket), socket.assigns.lead.id) do
      {:ok, lead} ->
        socket
        |> assign(lead: lead)
        |> stream(:interests, Enum.map(lead.interests, &interest_item/1), reset: true)

      {:error, :not_found} ->
        push_navigate(socket, to: ~p"/interesados")
    end
  end

  defp find_interest(socket, id) do
    Enum.find(socket.assigns.lead.interests, &(to_string(&1.id) == id))
  end

  defp interest_item(interest, changeset \\ nil) do
    changeset = changeset || Leads.change_interest(interest)
    action = if changeset.changes == %{}, do: nil, else: :validate

    %{
      id: interest.id,
      interest: interest,
      form: to_form(changeset, as: :interest, id: "interest-#{interest.id}", action: action)
    }
  end

  @doc false
  # Properties and rooms a lead can be linked to, as select options whose value
  # is "property_id" or "property_id-room_id". Also used by the WhatsApp inbox.
  def target_options(scope) do
    scope
    |> Properties.list_properties(:active)
    |> Enum.flat_map(fn property ->
      rooms =
        Enum.map(property.rooms, &{"#{property.name} · #{&1.name}", "#{property.id}-#{&1.id}"})

      [{property.name, to_string(property.id)} | rooms]
    end)
  end

  @doc false
  def parse_target(target) do
    case String.split(target, "-", parts: 2) do
      [property_id, room_id] -> {property_id, room_id}
      [property_id] -> {property_id, nil}
    end
  end

  # The unsaved choice while editing, else the stored outcome.
  defp check_value(form, key, outcome) do
    case form[:checks].value do
      %{^key => value} -> value
      _ -> outcome
    end
  end

  defp place(%Interest{room: nil, property: property}), do: property.name
  defp place(%Interest{room: room, property: property}), do: "#{property.name} · #{room.name}"

  defp scope(socket), do: socket.assigns.current_scope
end
