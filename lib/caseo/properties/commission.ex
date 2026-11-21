defmodule Caseo.Properties.Commission do
  @moduledoc """
  The owner's fee for a property or room, and its estimate.

  Sales charge a percentage of the price or a fixed amount. Rentals charge a
  number of monthly rents, a percentage of the annual rent or a fixed amount.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Caseo.Properties.Requirements

  @type t :: %__MODULE__{}

  @vat Decimal.new("1.21")

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum, values: [:percent, :months, :fixed]
    field :value, :decimal
    field :vat, :boolean, default: false
    field :payer, Ecto.Enum, values: [:owner, :tenant], default: :owner
  end

  @doc "Commission kinds available in a mode, with their labels."
  def kind_options(:sale), do: [{"% del precio", :percent}, {"Importe fijo (€)", :fixed}]

  def kind_options(_mode) do
    [
      {"Mensualidades de renta", :months},
      {"% de la renta anual", :percent},
      {"Importe fijo (€)", :fixed}
    ]
  end

  @spec changeset(t(), map(), atom()) :: Ecto.Changeset.t()
  def changeset(commission, attrs, mode \\ :rental) do
    attrs = Requirements.decimal_comma(attrs, "value")
    kinds = Enum.map(kind_options(mode), &elem(&1, 1))

    changeset =
      commission
      |> cast(attrs, [:kind, :value, :vat, :payer])
      |> validate_inclusion(:kind, kinds, message: "no está disponible en esta modalidad")

    changeset =
      case get_field(changeset, :kind) do
        nil -> change(changeset, value: nil, vat: false)
        :percent -> validate_value(changeset, less_than_or_equal_to: 100)
        :months -> validate_value(changeset, less_than_or_equal_to: 24)
        :fixed -> validate_value(changeset, less_than: 10_000_000_000)
      end

    if mode == :sale, do: put_change(changeset, :payer, nil), else: changeset
  end

  defp validate_value(changeset, max) do
    changeset
    |> validate_required([:value], message: "indica la comisión")
    |> validate_number(:value, [greater_than: 0] ++ max)
  end

  @doc """
  Estimates the commission in cents for a sale price or monthly rent in
  cents. Returns `nil` when either is unknown.
  """
  @spec estimate(t() | nil, atom(), integer() | nil) :: integer() | nil
  def estimate(%__MODULE__{kind: kind, value: %Decimal{} = value} = commission, mode, price)
      when is_integer(price) do
    base =
      case {kind, mode} do
        {:fixed, _} -> Decimal.mult(value, 100)
        {:months, _} -> Decimal.mult(value, price)
        {:percent, :sale} -> value |> Decimal.mult(price) |> Decimal.div(100)
        {:percent, _} -> value |> Decimal.mult(price * 12) |> Decimal.div(100)
      end

    base = if commission.vat, do: Decimal.mult(base, @vat), else: base
    base |> Decimal.round(0) |> Decimal.to_integer()
  end

  def estimate(_commission, _mode, _price), do: nil
end
