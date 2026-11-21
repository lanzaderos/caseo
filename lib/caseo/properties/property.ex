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
    field :rental_term, Ecto.Enum, values: [:long_term, :temporary]
    field :available_until, :date
    field :minimum_months, :integer
    field :maximum_months, :integer
    field :for_students, :boolean, default: false
    field :academic_year, :string
    field :archived_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Validates editable data and converts the monthly rent to integer cents."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(property, attrs) do
    %{property | rent: formatted_rent(property)}
    |> cast(attrs, [
      :name,
      :rent,
      :available_on,
      :rental_term,
      :for_students
    ])
    |> change_rental_term(attrs)
    |> change_student_details(attrs)
    |> validate_required([:name, :rent, :for_students])
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

  defp change_rental_term(changeset, attrs) do
    if get_field(changeset, :rental_term) == :temporary do
      changeset
      |> cast(attrs, [:available_until, :minimum_months, :maximum_months])
      |> validate_required([:available_on])
      |> validate_number(:minimum_months, greater_than: 0, less_than_or_equal_to: 2_147_483_647)
      |> validate_number(:maximum_months, greater_than: 0, less_than_or_equal_to: 2_147_483_647)
      |> validate_temporary_ranges()
    else
      change(changeset, available_until: nil, minimum_months: nil, maximum_months: nil)
    end
  end

  defp validate_temporary_ranges(changeset) do
    starts_on = get_field(changeset, :available_on)
    ends_on = get_field(changeset, :available_until)
    minimum = get_field(changeset, :minimum_months)
    maximum = get_field(changeset, :maximum_months)

    changeset =
      if starts_on && ends_on && Date.compare(ends_on, starts_on) != :gt do
        add_error(changeset, :available_until, "debe ser posterior a la fecha de inicio")
      else
        changeset
      end

    if minimum && maximum && maximum < minimum do
      add_error(changeset, :maximum_months, "debe ser igual o superior a la estancia mínima")
    else
      changeset
    end
  end

  defp change_student_details(changeset, attrs) do
    if get_field(changeset, :for_students) do
      changeset |> cast(attrs, [:academic_year]) |> validate_length(:academic_year, max: 100)
    else
      put_change(changeset, :academic_year, nil)
    end
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
