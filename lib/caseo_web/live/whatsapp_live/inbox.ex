defmodule CaseoWeb.WhatsappLive.Inbox do
  use CaseoWeb, :live_view

  alias Caseo.Leads
  alias Caseo.Leads.Interest
  alias Caseo.Leads.Lead
  alias Caseo.Properties
  alias Caseo.Visits
  alias Caseo.Whatsapp
  alias Caseo.Whatsapp.Account
  alias Caseo.Whatsapp.Message
  alias CaseoWeb.LeadLive.Show, as: LeadShow

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Whatsapp.subscribe(scope)

    {:ok,
     socket
     |> assign(
       page_title: "WhatsApp",
       account: Whatsapp.get_account(scope),
       target_options: LeadShow.target_options(scope),
       schedule: nil
     )
     |> load_conversations()}
  end

  @impl true
  def handle_params(%{"phone" => digits}, _uri, socket) do
    phone = Lead.normalize_phone("+" <> digits)
    scope = socket.assigns.current_scope
    Whatsapp.mark_read(scope, phone)
    messages = Whatsapp.list_messages(scope, phone)

    {:noreply,
     socket
     |> assign(phone: phone, schedule: nil, message_form: message_form())
     |> stream(:messages, messages, reset: true)
     |> load_conversations()
     |> load_panel(messages)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(phone: nil, lead: nil, suggestion: nil, visits: [], schedule: nil)
     |> stream(:messages, [], reset: true)}
  end

  @impl true
  def handle_event("send", %{"message" => %{"body" => body}}, socket) do
    case Whatsapp.send_text(socket.assigns.current_scope, socket.assigns.phone, body) do
      {:ok, _message} ->
        {:noreply, assign(socket, message_form: message_form())}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(message_form: message_form(body))
         |> put_flash(:error, send_error(reason))}
    end
  end

  def handle_event("create_lead", %{"lead" => params}, socket) do
    params = Map.merge(params, %{"phone" => socket.assigns.phone, "source" => "whatsapp"})

    case Leads.create_lead(socket.assigns.current_scope, params) do
      {:ok, _lead} ->
        {:noreply, socket |> put_flash(:info, "Interesado creado.") |> reload_panel()}

      {:error, changeset} ->
        {:noreply, assign(socket, lead_form: to_form(changeset))}
    end
  end

  def handle_event("link", %{"link" => %{"target" => target}}, socket) do
    {property_id, room_id} = LeadShow.parse_target(target)
    add_interest(socket, property_id, room_id)
  end

  def handle_event("link_suggested", _params, socket) do
    {property, room} = socket.assigns.suggestion
    add_interest(socket, property.id, room && room.id)
  end

  def handle_event("open_schedule", %{"id" => id}, socket) do
    interest = Enum.find(socket.assigns.lead.interests, &(to_string(&1.id) == id))
    {:noreply, assign(socket, schedule: interest)}
  end

  def handle_event("close_schedule", _params, socket),
    do: {:noreply, assign(socket, schedule: nil)}

  @impl true
  def handle_info({:whatsapp_message, %Message{} = message}, socket) do
    socket = load_conversations(socket)

    if message.contact_phone == socket.assigns.phone do
      Whatsapp.mark_read(socket.assigns.current_scope, message.contact_phone)

      socket =
        if message.direction == :inbound and is_nil(socket.assigns.suggestion),
          do: assign(socket, suggestion: suggestion(socket, [message])),
          else: socket

      {:noreply, stream_insert(socket, :messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:whatsapp_account, account}, socket),
    do: {:noreply, assign(socket, account: account)}

  defp add_interest(socket, property_id, room_id) do
    case Leads.add_interest(
           socket.assigns.current_scope,
           socket.assigns.lead.id,
           property_id,
           room_id
         ) do
      {:ok, _interest} ->
        {:noreply, socket |> put_flash(:info, "Inmueble vinculado.") |> reload_panel()}

      {:error, :already_linked} ->
        {:noreply, put_flash(socket, :error, "Ya está vinculado a ese inmueble.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Elige un inmueble.")}
    end
  end

  defp load_conversations(socket) do
    assign(socket, conversations: Whatsapp.list_conversations(socket.assigns.current_scope))
  end

  defp reload_panel(socket) do
    load_panel(socket, Whatsapp.list_messages(socket.assigns.current_scope, socket.assigns.phone))
  end

  # The lead behind the chat (if any), their properties and visits, and a
  # property suggested by an Idealista link in the chat.
  defp load_panel(socket, messages) do
    scope = socket.assigns.current_scope
    lead = Leads.get_lead_by_phone(scope, socket.assigns.phone)
    name = Enum.find_value(Enum.reverse(messages), & &1.contact_name)

    assign(socket,
      lead: lead,
      lead_form: to_form(%{"name" => name || ""}, as: :lead),
      link_form: to_form(%{"target" => ""}, as: :link),
      visits: if(lead, do: Visits.list_visits(scope, lead_id: lead.id), else: []),
      suggestion: suggestion(socket, messages)
    )
  end

  defp suggestion(socket, messages) do
    text =
      messages
      |> Enum.filter(&(&1.direction == :inbound and &1.body))
      |> Enum.map_join("\n", & &1.body)

    Properties.find_linked_listing(socket.assigns.current_scope, text)
  end

  defp message_form(body \\ ""), do: to_form(%{"body" => body}, as: :message)

  defp send_error(:not_linked), do: "Vincula tu número de WhatsApp para responder."

  defp send_error(:unknown_contact),
    do: "Solo puedes escribir a quien te haya escrito o sea tu interesado."

  defp send_error(:empty), do: "Escribe un mensaje."

  defp send_error(:rate_limited),
    do: "Has llegado al límite de mensajes por hora. Inténtalo más tarde."

  defp send_error(_reason), do: "No se pudo enviar el mensaje. Inténtalo de nuevo."

  defp title(%{contact_name: name}) when is_binary(name), do: name
  defp title(%{contact_phone: phone}), do: phone

  defp chat_title(nil, conversations, phone) do
    case Enum.find(conversations, &(&1.contact_phone == phone)) do
      nil -> phone
      conversation -> title(conversation)
    end
  end

  defp chat_title(%Lead{name: name}, _conversations, _phone), do: name

  defp digits(phone), do: String.trim_leading(phone, "+")

  defp place(%Interest{room: nil, property: property}), do: property.name
  defp place(%Interest{room: room, property: property}), do: "#{property.name} · #{room.name}"

  defp suggestion_label({property, nil}), do: property.name
  defp suggestion_label({property, room}), do: "#{property.name} · #{room.name}"

  defp already_linked?(%Lead{interests: interests}, {property, room}) do
    Enum.any?(interests, &(&1.property_id == property.id and &1.room_id == (room && room.id)))
  end
end
