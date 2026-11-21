defmodule CaseoWeb.PropertyLive.Form do
  use CaseoWeb, :live_view

  alias Caseo.Properties
  alias Caseo.Properties.Commission
  alias Caseo.Properties.Property
  alias Caseo.Properties.Requirements

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

  attr :form, Phoenix.HTML.Form, required: true

  defp rental_fields(assigns) do
    ~H"""
    <.input
      field={@form[:rent]}
      label="Renta mensual (€)"
      inputmode="decimal"
      placeholder="850,00"
      required
    />
    <.input
      field={@form[:rental_term]}
      type="select"
      label="Duración del alquiler"
      options={[
        {"Por confirmar", ""},
        {"Larga duración", :long_term},
        {"Temporal", :temporary}
      ]}
    />
    <.input
      field={@form[:available_on]}
      type="date"
      label="Disponible desde"
      required={@form[:rental_term].value in [:temporary, "temporary"]}
    />
    <%= if @form[:rental_term].value in [:temporary, "temporary"] do %>
      <.input field={@form[:available_until]} type="date" label="Disponible hasta" />
      <.input
        field={@form[:minimum_months]}
        type="number"
        min="1"
        label="Estancia mínima (meses)"
      />
      <.input
        field={@form[:maximum_months]}
        type="number"
        min="1"
        label="Estancia máxima (meses)"
      />
    <% end %>
    <div class="sm:col-span-2">
      <.input field={@form[:for_students]} type="checkbox" label="Orientado a estudiantes" />
    </div>
    <.input
      :if={Phoenix.HTML.Form.normalize_value("checkbox", @form[:for_students].value)}
      field={@form[:academic_year]}
      label="Curso académico (opcional)"
      placeholder="2026–2027"
      maxlength="100"
    />
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :mode, :atom, required: true

  defp terms_fields(assigns) do
    ~H"""
    <.inputs_for :let={req} field={@form[:requirements]}>
      <fieldset class="sm:col-span-2 grid gap-x-4 sm:grid-cols-2">
        <legend class="mb-2 font-semibold">Requisitos</legend>
        <.input
          field={req[:payslips]}
          type="number"
          min="1"
          max="24"
          label="Nóminas recientes (opcional)"
        />
        <div :if={@mode != :sale}>
          <.input
            field={req[:income_multiple]}
            inputmode="decimal"
            label="Ingresos mínimos (× renta, opcional)"
            placeholder="3"
          />
        </div>
        <fieldset class="sm:col-span-2 mb-2">
          <legend class="label mb-1 text-sm">
            Contratos admitidos (ninguno marcado: cualquiera)
          </legend>
          <input type="hidden" name={req[:contract_types].name <> "[]"} value="" />
          <div class="flex flex-wrap gap-x-4">
            <label :for={{label, value} <- Requirements.contract_options()} class="label">
              <input
                type="checkbox"
                name={req[:contract_types].name <> "[]"}
                value={value}
                checked={value in contract_values(req[:contract_types].value)}
                class="checkbox checkbox-sm"
              />
              {label}
            </label>
          </div>
        </fieldset>
        <%= if @mode != :sale do %>
          <.input
            field={req[:deposit_months]}
            type="number"
            min="0"
            max="12"
            label="Meses de fianza"
          />
          <.input
            field={req[:extra_guarantee_months]}
            type="number"
            min="0"
            max="12"
            label="Meses de garantía adicional"
          />
        <% end %>
        <.input field={req[:guarantee]} type="checkbox" label="Aval o seguro de impago" />
        <.input field={req[:pets_allowed]} type="checkbox" label="Se admiten mascotas" />
        <.input field={req[:smokers_allowed]} type="checkbox" label="Se admiten fumadores" />
        <div class="sm:col-span-2">
          <.input field={req[:other]} label="Otro requisito (opcional)" maxlength="500" />
          <p class="workspace-muted text-xs">
            No se admiten criterios discriminatorios como nacionalidad, origen o tener hijos.
          </p>
        </div>
      </fieldset>
    </.inputs_for>
    <.inputs_for :let={fee} field={@form[:commission]}>
      <fieldset class="sm:col-span-2 grid gap-x-4 sm:grid-cols-2">
        <legend class="mb-2 font-semibold">Comisión</legend>
        <.input
          field={fee[:kind]}
          type="select"
          label="Tipo"
          prompt="Sin comisión"
          options={Commission.kind_options(@mode)}
        />
        <.input
          :if={fee[:kind].value not in [nil, ""]}
          field={fee[:value]}
          inputmode="decimal"
          label={value_label(fee[:kind].value)}
        />
        <.input field={fee[:vat]} type="checkbox" label="Más IVA (21 %)" />
        <div :if={@mode != :sale}>
          <.input
            field={fee[:payer]}
            type="select"
            label="La paga"
            options={[{"El propietario", :owner}, {"El inquilino", :tenant}]}
          />
          <p
            :if={fee[:payer].value in [:tenant, "tenant"]}
            class="text-warning text-xs"
          >
            En vivienda habitual, los gastos de gestión inmobiliaria corren a cargo del
            arrendador (Ley 12/2023).
          </p>
        </div>
      </fieldset>
    </.inputs_for>
    """
  end

  defp contract_values(values), do: Enum.map(List.wrap(values), &to_string/1)

  defp value_label(kind) when kind in [:percent, "percent"], do: "Porcentaje (%)"
  defp value_label(kind) when kind in [:months, "months"], do: "Número de mensualidades"
  defp value_label(_kind), do: "Importe (€)"

  defp form_mode(form) do
    case form[:mode].value do
      mode when mode in [:sale, "sale"] -> :sale
      mode when mode in [:rooms, "rooms"] -> :rooms
      _ -> :rental
    end
  end

  defp address_errors?(form) do
    form.source.action in [:insert, :update] &&
      Enum.any?(
        [:street, :municipality, :postal_code, :province, :latitude, :longitude],
        fn field ->
          form[field].errors != []
        end
      )
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
