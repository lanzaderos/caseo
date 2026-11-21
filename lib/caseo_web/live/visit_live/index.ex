defmodule CaseoWeb.VisitLive.Index do
  use CaseoWeb, :live_view

  alias Caseo.Properties
  alias Caseo.Visits
  alias Caseo.Visits.Visit

  @impl true
  def mount(_params, _session, socket) do
    properties = Properties.list_properties(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: "Agenda",
       property_options: Enum.map(properties, &{&1.name, to_string(&1.id)})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    property_id =
      case Integer.parse(params["inmueble"] || "") do
        {id, ""} -> id
        _ -> nil
      end

    visits = Visits.list_visits(socket.assigns.current_scope, property_id: property_id)

    {:noreply,
     assign(socket,
       filter_form: to_form(%{"inmueble" => params["inmueble"] || ""}),
       days: Enum.chunk_by(visits, &NaiveDateTime.to_date(&1.starts_at))
     )}
  end

  @impl true
  def handle_event("filter", %{"inmueble" => ""}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/visitas")}

  def handle_event("filter", %{"inmueble" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/visitas?#{[inmueble: id]}")}

  @weekdays ~w(lunes martes miércoles jueves viernes sábado domingo)
  @months ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)

  @doc false
  def day_label(date) do
    weekday = Enum.at(@weekdays, Date.day_of_week(date) - 1)
    month = Enum.at(@months, date.month - 1)
    String.capitalize("#{weekday} #{date.day} de #{month}")
  end

  defp place(%{room: nil, property: property}), do: property.name
  defp place(%{room: room, property: property}), do: "#{property.name} · #{room.name}"

  defp status_class(:cancelled), do: "workspace-muted line-through"
  defp status_class(:no_show), do: "workspace-muted"
  defp status_class(_status), do: nil

  defp time(visit), do: Calendar.strftime(visit.starts_at, "%H:%M")
  defp end_time(visit), do: Calendar.strftime(Visit.ends_at(visit), "%H:%M")
end
