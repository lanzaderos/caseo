defmodule CaseoWeb.ScheduleVisitComponent do
  @moduledoc """
  The "Agendar visita" dialog for a lead's interest: pick the date manually or
  send a booking link. With a linked WhatsApp number the link goes out from
  Caseo; otherwise it opens WhatsApp on the owner's device.

  The parent renders it while an interest is selected and handles the
  `"close_schedule"` event.
  """

  use CaseoWeb, :live_component

  alias Caseo.Visits
  alias Caseo.Whatsapp

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if changed?(socket, :interest) do
        assign(socket,
          booking_url: nil,
          sent: nil,
          free_slot_count: length(Visits.free_slots(assigns.current_scope))
        )
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("create_booking_link", _params, socket) do
    case Visits.create_booking_link(socket.assigns.current_scope, socket.assigns.interest.id) do
      {:ok, token} ->
        {:noreply, assign(socket, booking_url: url(~p"/reservar/#{token}"), sent: nil)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("revoke_booking_link", _params, socket) do
    Visits.revoke_booking_links(socket.assigns.current_scope, socket.assigns.interest.id)
    {:noreply, assign(socket, booking_url: nil, sent: nil)}
  end

  def handle_event("send_booking_link", _params, socket) do
    %{current_scope: scope, lead: lead, interest: interest, booking_url: url} = socket.assigns

    result =
      case Whatsapp.send_text(scope, lead.phone, message(lead, interest, url)) do
        {:ok, _message} ->
          :ok

        {:error, :rate_limited} ->
          "Has llegado al límite de mensajes por hora. Inténtalo más tarde."

        {:error, _reason} ->
          "No se pudo enviar por WhatsApp. Copia el enlace y envíalo a mano."
      end

    {:noreply, assign(socket, sent: result)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="modal modal-open"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown="close_schedule"
      phx-key="Escape"
    >
      <div class="modal-box workspace-glass max-w-lg space-y-4" lang="es">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 id={"#{@id}-title"} class="text-lg font-semibold">Agendar visita</h2>
            <p class="workspace-muted text-sm">{@lead.name} · {place(@interest)}</p>
          </div>
          <button
            type="button"
            phx-click="close_schedule"
            class="btn btn-sm btn-ghost btn-square"
            aria-label="Cerrar"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <.link
          id="schedule-manually"
          navigate={~p"/visitas/nueva?#{[interes: @interest.id]}"}
          class="workspace-divider flex items-center gap-3 rounded-xl border p-4 transition hover:bg-base-content/5"
        >
          <.icon name="hero-calendar-days" class="size-6 shrink-0" />
          <span>
            <span class="block font-semibold">Elegir yo la fecha</span>
            <span class="workspace-muted text-sm">
              Agenda la visita en un hueco libre o a la hora que acordéis.
            </span>
          </span>
        </.link>

        <div class="workspace-divider space-y-3 rounded-xl border p-4">
          <div class="flex items-center gap-3">
            <.icon name="hero-paper-airplane" class="size-6 shrink-0" />
            <span>
              <span class="block font-semibold">Enviar enlace de reserva</span>
              <span class="workspace-muted text-sm">
                {@lead.name} elige uno de tus {@free_slot_count} huecos libres y tú apruebas la visita.
              </span>
            </span>
          </div>
          <p :if={@free_slot_count == 0} class="text-warning text-sm">
            No tienes huecos libres.
            <.link navigate={~p"/visitas/disponibilidad"} class="link">
              Marca tu disponibilidad
            </.link>
            antes de enviar el enlace.
          </p>
          <%= if @booking_url do %>
            <label for="booking-url" class="sr-only">Enlace de reserva</label>
            <input
              id="booking-url"
              type="text"
              readonly
              value={@booking_url}
              class="input input-sm w-full"
            />
            <div class="flex flex-wrap gap-2">
              <%= if @whatsapp_linked do %>
                <button
                  id="send-booking-whatsapp"
                  type="button"
                  phx-click="send_booking_link"
                  phx-target={@myself}
                  phx-disable-with="Enviando…"
                  disabled={@sent == :ok}
                  class="btn workspace-primary btn-sm rounded-lg"
                >
                  {if(@sent == :ok, do: "Enviado", else: "Enviar por WhatsApp")}
                </button>
              <% else %>
                <a
                  id="send-booking-whatsapp"
                  href={wa_me_url(@lead, @interest, @booking_url)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="btn workspace-primary btn-sm rounded-lg"
                >
                  Enviar por WhatsApp
                </a>
              <% end %>
              <button
                id="copy-booking-url"
                type="button"
                phx-click={JS.dispatch("phx:copy", to: "#booking-url")}
                class="btn btn-ghost btn-sm rounded-lg"
              >
                <.icon name="hero-clipboard" class="size-4" /> Copiar
              </button>
              <button
                id="revoke-booking-link"
                type="button"
                phx-click="revoke_booking_link"
                phx-target={@myself}
                class="btn btn-ghost btn-sm text-error ms-auto rounded-lg"
              >
                Revocar
              </button>
            </div>
            <p :if={is_binary(@sent)} id="booking-send-error" class="text-error text-sm">
              {@sent}
            </p>
            <p class="workspace-muted text-xs">Caduca en 7 días. Generar otro revoca este.</p>
          <% else %>
            <button
              id="create-booking-link"
              type="button"
              phx-click="create_booking_link"
              phx-target={@myself}
              disabled={@free_slot_count == 0}
              class="btn workspace-primary btn-sm rounded-lg"
            >
              Generar enlace
            </button>
          <% end %>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_schedule"></div>
    </div>
    """
  end

  defp message(lead, interest, url) do
    first_name = lead.name |> String.split() |> List.first()
    "Hola #{first_name}, elige cuándo quieres visitar #{place(interest)}: #{url}"
  end

  # Opens WhatsApp (web or app) on the owner's device with the message ready.
  defp wa_me_url(lead, interest, url) do
    text = URI.encode(message(lead, interest, url), &URI.char_unreserved?/1)
    "https://wa.me/#{String.trim_leading(lead.phone, "+")}?text=#{text}"
  end

  defp place(%{room: nil, property: property}), do: property.name
  defp place(%{room: room, property: property}), do: "#{property.name} · #{room.name}"
end
