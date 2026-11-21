defmodule Caseo.Properties.Property do
  @moduledoc "A rental property owned by a Caseo account."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "properties" do
    belongs_to :owner, Caseo.Accounts.User
    field :name, :string
    field :rent_cents, :integer
    field :rent, :string, virtual: true
    field :available_on, :date
    field :archived_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Validates editable data and converts the monthly rent to integer cents."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(property, attrs) do
    %{property | rent: formatted_rent(property)}
    |> cast(attrs, [:name, :rent, :available_on])
    |> validate_required([:name, :rent])
    |> validate_length(:name, max: 255)
    |> validate_format(:rent, ~r/\A[0-9]{1,12}(?:[,.][0-9]{1,2})?\z/,
      message: "introduce un importe con hasta dos decimales"
    )
    |> put_rent_cents()
  end

  @doc "Formats the monthly rent in euros, with a decimal comma."
  @spec formatted_rent(t()) :: String.t() | nil
  def formatted_rent(%__MODULE__{rent_cents: nil}), do: nil

  def formatted_rent(%__MODULE__{rent_cents: cents}) do
    decimals = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{div(cents, 100)},#{decimals}"
  end

  defp put_rent_cents(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp put_rent_cents(changeset) do
    [euros | decimals] = changeset |> get_field(:rent) |> String.split([",", "."])
    fraction = decimals |> List.first("0") |> String.pad_trailing(2, "0")
    cents = String.to_integer(euros) * 100 + String.to_integer(fraction)

    if cents > 0 do
      put_change(changeset, :rent_cents, cents)
    else
      add_error(changeset, :rent, "debe ser mayor que cero")
    end
  end
end
