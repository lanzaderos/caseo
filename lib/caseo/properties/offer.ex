defmodule Caseo.Properties.Offer do
  @moduledoc false

  import Ecto.Changeset

  def format_amount(nil), do: nil

  def format_amount(cents) do
    decimals = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{div(cents, 100)},#{decimals}"
  end

  def change_amount(changeset, attrs, field, cents_field) do
    changeset
    |> cast(attrs, [field])
    |> validate_required([field])
    |> validate_format(field, ~r/\A[0-9]{1,12}(?:[,.][0-9]{1,2})?\z/,
      message: "introduce un importe con hasta dos decimales"
    )
    |> put_cents(field, cents_field)
  end

  def change_rental(changeset, attrs) do
    changeset
    |> cast(attrs, [:available_on, :rental_term, :for_students])
    |> validate_required([:for_students])
    |> change_rental_term(attrs)
    |> change_student_details(attrs)
  end

  def clear_rental(changeset) do
    change(changeset,
      rental_term: nil,
      available_until: nil,
      minimum_months: nil,
      maximum_months: nil,
      for_students: false,
      academic_year: nil
    )
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

  defp put_cents(%Ecto.Changeset{valid?: false} = changeset, _field, _cents_field), do: changeset

  defp put_cents(changeset, field, cents_field) do
    [euros | decimals] = changeset |> get_field(field) |> String.split([",", "."])
    fraction = decimals |> List.first("0") |> String.pad_trailing(2, "0")
    cents = String.to_integer(euros) * 100 + String.to_integer(fraction)

    if cents > 0 do
      put_change(changeset, cents_field, cents)
    else
      add_error(changeset, field, "debe ser mayor que cero")
    end
  end
end
