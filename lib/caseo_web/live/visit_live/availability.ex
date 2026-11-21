defmodule CaseoWeb.VisitLive.Availability do
  use CaseoWeb, :live_view

  alias Caseo.Visits
  alias Caseo.Visits.AvailabilityWindow
  alias CaseoWeb.VisitLive.Index

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Disponibilidad", form: new_form())
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"availability_window" => params}, socket) do
    form =
      %AvailabilityWindow{}
      |> Visits.change_window(params)
      |> to_form(action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"availability_window" => params}, socket) do
    case Visits.create_window(socket.assigns.current_scope, params) do
      {:ok, _window} ->
        {:noreply,
         socket
         |> assign(form: new_form())
         |> put_flash(:info, "Franja añadida.")
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Visits.delete_window(socket.assigns.current_scope, id)
    {:noreply, socket |> put_flash(:info, "Franja eliminada.") |> load()}
  end

  # Each window with its free and total slots; weekly ones count every
  # upcoming week within the booking horizon.
  defp load(socket) do
    scope = socket.assigns.current_scope
    now = NaiveDateTime.local_now()
    free = scope |> Visits.free_slots() |> MapSet.new(&elem(&1, 0))

    {weekly, one_off} =
      scope
      |> Visits.list_windows()
      |> Enum.map(fn window ->
        slots =
          window
          |> AvailabilityWindow.occurrences(now)
          |> Enum.flat_map(&AvailabilityWindow.slots/1)

        {window, Enum.count(slots, &MapSet.member?(free, &1)), length(slots)}
      end)
      |> Enum.split_with(fn {window, _, _} -> window.weekly end)

    assign(socket,
      weekly: weekly,
      days: Enum.chunk_by(one_off, fn {w, _, _} -> NaiveDateTime.to_date(w.starts_at) end)
    )
  end

  defp new_form do
    to_form(Visits.change_window(%AvailabilityWindow{}, %{"slot_minutes" => "30"}))
  end

  @weekdays ~w(lunes martes miércoles jueves viernes sábado domingo)

  defp weekly_label(window) do
    weekday = Enum.at(@weekdays, Date.day_of_week(NaiveDateTime.to_date(window.starts_at)) - 1)
    "Cada #{weekday}"
  end

  defp day_label(date), do: Index.day_label(date)
  defp hour(time), do: Calendar.strftime(time, "%H:%M")
  defp short_date(date), do: Calendar.strftime(date, "%d/%m/%Y")
end
