defmodule CaseoWeb.VisitLive.Booking do
  @moduledoc "Public page where a lead requests a visit slot through their link."

  use CaseoWeb, :live_view

  alias Caseo.Visits
  alias Caseo.Visits.BookingLink
  alias CaseoWeb.VisitLive.Index

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, page_title: "Reservar visita", token: token)

    case Visits.fetch_booking_link(token) do
      {:ok, link} -> {:ok, load(socket, link)}
      {:error, :not_found} -> {:ok, assign(socket, link: nil)}
    end
  end

  @impl true
  def handle_event("book", %{"slot" => slot}, socket) do
    case Visits.book(socket.assigns.token, slot) do
      {:ok, _visit} ->
        {:ok, link} = Visits.fetch_booking_link(socket.assigns.token)
        {:noreply, load(socket, link)}

      {:error, :slot_taken} ->
        {:ok, link} = Visits.fetch_booking_link(socket.assigns.token)

        {:noreply,
         socket
         |> put_flash(:error, "Ese hueco ya no está libre. Elige otro.")
         |> load(link)}

      {:error, _closed} ->
        {:noreply, put_flash(socket, :error, "Este enlace ya no admite reservas.")}
    end
  end

  defp load(socket, link) do
    days =
      if BookingLink.open?(link) do
        link.interest.lead.owner_id
        |> Visits.free_slots()
        |> Enum.chunk_by(&NaiveDateTime.to_date(elem(&1, 0)))
      else
        []
      end

    assign(socket, link: link, open?: BookingLink.open?(link), days: days)
  end

  defp first_name(name), do: name |> String.split() |> List.first()

  defp place(%{room: nil, property: property}), do: property.name
  defp place(%{room: room, property: property}), do: "#{property.name} · #{room.name}"

  defp day_label(date), do: Index.day_label(date)
  defp hour(time), do: Calendar.strftime(time, "%H:%M")
end
