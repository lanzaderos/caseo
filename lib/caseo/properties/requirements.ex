defmodule Caseo.Properties.Requirements do
  @moduledoc """
  What the owner asks of a lead for a property or room.

  The fields are a fixed template so that no selection criterion can be based
  on protected traits (nationality, children, etc.). The free-text requirement
  is checked against the most common discriminatory terms.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Caseo.Properties.Offer

  @type t :: %__MODULE__{}

  @contract_types [:permanent, :temporary, :self_employed, :student]

  @primary_key false
  embedded_schema do
    field :payslips, :integer
    field :contract_types, {:array, Ecto.Enum}, values: @contract_types, default: []
    field :income_multiple, :decimal
    field :guarantee, :boolean, default: false
    field :deposit_months, :integer
    field :extra_guarantee_months, :integer
    field :pets_allowed, :boolean, default: true
    field :smokers_allowed, :boolean, default: true
    field :other, :string
  end

  # ponytail: keyword screen for the free-text field; it catches the obvious
  # cases, a human review of #12 covers the rest.
  @discriminatory ~r/\b(nacionalidad|extranjer|nativo|nativa|raza|racial|etnia|étnic|gitan|religi|musulm|sexo|género|orientación sexual|embaraz|hijos|hijas|niños|niñas|bebés?|discapacid|minusválid|estado civil)/iu

  @doc "Contract types a lead may have, with their labels."
  def contract_options do
    [
      {"Indefinido", :permanent},
      {"Temporal", :temporary},
      {"Autónomo", :self_employed},
      {"Estudiante o sin ingresos", :student}
    ]
  end

  @doc """
  Validates the requirements. Rent-based fields (income, deposit) do not apply
  to sales and are cleared.
  """
  @spec changeset(t(), map(), atom()) :: Ecto.Changeset.t()
  def changeset(requirements, attrs, mode \\ :rental) do
    # The form sends an empty value so that unticking every contract clears them.
    attrs =
      attrs
      |> decimal_comma("income_multiple")
      |> Map.replace_lazy("contract_types", &Enum.reject(List.wrap(&1), fn t -> t == "" end))

    changeset =
      requirements
      |> cast(attrs, [
        :payslips,
        :contract_types,
        :income_multiple,
        :guarantee,
        :deposit_months,
        :extra_guarantee_months,
        :pets_allowed,
        :smokers_allowed,
        :other
      ])
      |> validate_number(:payslips, greater_than: 0, less_than_or_equal_to: 24)
      |> validate_number(:income_multiple, greater_than: 0, less_than_or_equal_to: 10)
      |> validate_number(:deposit_months, greater_than_or_equal_to: 0, less_than_or_equal_to: 12)
      |> validate_number(:extra_guarantee_months,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 12
      )
      |> validate_length(:other, max: 500)
      |> validate_change(:other, fn :other, text ->
        if Regex.match?(@discriminatory, text),
          do: [other: "no puede incluir criterios discriminatorios"],
          else: []
      end)

    if mode == :sale,
      do:
        change(changeset, income_multiple: nil, deposit_months: nil, extra_guarantee_months: nil),
      else: changeset
  end

  @doc """
  Lists the requirements as checklist items `{key, label}`. `rent_cents` turns
  the income multiple into an amount when known.
  """
  @spec checklist(t() | nil, integer() | nil) :: [{String.t(), String.t()}]
  def checklist(nil, _rent_cents), do: []

  def checklist(%__MODULE__{} = r, rent_cents) do
    [
      r.payslips && {"payslips", payslips_label(r.payslips)},
      r.contract_types != [] && {"contract", "Contrato #{contract_labels(r.contract_types)}"},
      r.income_multiple && {"income", income_label(r.income_multiple, rent_cents)},
      r.guarantee && {"guarantee", "Aval o seguro de impago"},
      deposit_item(r),
      !r.pets_allowed && {"pets", "Sin mascotas"},
      !r.smokers_allowed && {"smokers", "No fumador"},
      r.other not in [nil, ""] && {"other", r.other}
    ]
    |> Enum.filter(& &1)
  end

  @doc "Every checklist key, for validating stored checks."
  def keys, do: ~w(payslips contract income guarantee deposit pets smokers other)

  defp payslips_label(1), do: "Última nómina"
  defp payslips_label(n), do: "#{n} últimas nóminas"

  defp contract_labels(types) do
    labels = Map.new(contract_options(), fn {label, value} -> {value, String.downcase(label)} end)
    Enum.map_join(types, " o ", &labels[&1])
  end

  defp income_label(multiple, nil), do: "Ingresos de #{format(multiple)}× la renta"

  defp income_label(multiple, rent_cents) do
    amount = multiple |> Decimal.mult(rent_cents) |> Decimal.round(0) |> Decimal.to_integer()

    "Ingresos de #{format(multiple)}× la renta (#{Offer.format_amount(amount)} €)"
  end

  defp deposit_item(r) do
    parts =
      Enum.filter(
        [
          (r.deposit_months || 0) > 0 && "fianza de #{months(r.deposit_months)}",
          (r.extra_guarantee_months || 0) > 0 &&
            "#{months(r.extra_guarantee_months)} de garantía adicional"
        ],
        & &1
      )

    parts != [] && {"deposit", "Pagar " <> Enum.join(parts, " y ")}
  end

  defp months(1), do: "1 mes"
  defp months(n), do: "#{n} meses"

  defp format(decimal),
    do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  @doc false
  def decimal_comma(attrs, key) do
    case attrs do
      %{^key => value} when is_binary(value) ->
        Map.put(attrs, key, String.replace(value, ",", "."))

      _ ->
        attrs
    end
  end
end
