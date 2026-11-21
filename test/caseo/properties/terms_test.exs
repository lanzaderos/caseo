defmodule Caseo.Properties.TermsTest do
  use Caseo.DataCase, async: true

  import Caseo.AccountsFixtures

  alias Caseo.Properties
  alias Caseo.Properties.Commission
  alias Caseo.Properties.Property
  alias Caseo.Properties.Requirements

  @address %{
    "street" => "Calle Mayor 12",
    "municipality" => "Madrid",
    "postal_code" => "28013",
    "province" => "Madrid"
  }

  test "estimates commissions by percentage, months and fixed amount, with and without VAT" do
    fee = &%Commission{kind: &1, value: Decimal.new(&2), vat: &3}

    # Sale of 200.000 €: 3 % → 6.000 €, plus VAT → 7.260 €.
    assert Commission.estimate(fee.(:percent, "3", false), :sale, 20_000_000) == 600_000
    assert Commission.estimate(fee.(:percent, "3", true), :sale, 20_000_000) == 726_000
    assert Commission.estimate(fee.(:fixed, "4500", false), :sale, 20_000_000) == 450_000

    # Rent of 900 €/month: 1 month, 10 % of the annual rent, 1.000 € fixed.
    assert Commission.estimate(fee.(:months, "1", false), :rental, 90_000) == 90_000
    assert Commission.estimate(fee.(:months, "1.5", true), :rental, 90_000) == 163_350
    assert Commission.estimate(fee.(:percent, "10", false), :rental, 90_000) == 108_000
    assert Commission.estimate(fee.(:fixed, "1000", true), :rental, 90_000) == 121_000

    assert Commission.estimate(%Commission{}, :rental, 90_000) == nil
    assert Commission.estimate(fee.(:months, "1", false), :rental, nil) == nil
  end

  test "configures requirements and commission in the three modes" do
    scope = user_scope_fixture()

    {:ok, rental} =
      Properties.create_property(
        scope,
        Map.merge(@address, %{
          "name" => "Piso",
          "mode" => "rental",
          "rent" => "900",
          "requirements" => %{
            "payslips" => "3",
            "contract_types" => ["", "permanent", "temporary"],
            "income_multiple" => "2,5",
            "deposit_months" => "1",
            "extra_guarantee_months" => "2",
            "pets_allowed" => "false"
          },
          "commission" => %{
            "kind" => "months",
            "value" => "1",
            "vat" => "true",
            "payer" => "owner"
          }
        })
      )

    assert Requirements.checklist(rental.requirements, 90_000) == [
             {"payslips", "3 últimas nóminas"},
             {"contract", "Contrato indefinido o temporal"},
             {"income", "Ingresos de 2,5× la renta (2250,00 €)"},
             {"deposit", "Pagar fianza de 1 mes y 2 meses de garantía adicional"},
             {"pets", "Sin mascotas"}
           ]

    assert Property.estimated_commission(rental) == 108_900

    {:ok, sale} =
      Properties.create_property(
        scope,
        Map.merge(@address, %{
          "name" => "Chalet",
          "mode" => "sale",
          "sale_price" => "300000",
          "requirements" => %{"income_multiple" => "3", "guarantee" => "true"},
          "commission" => %{"kind" => "percent", "value" => "3"}
        })
      )

    # Rent-based requirements and the payer do not apply to sales.
    assert sale.requirements.income_multiple == nil
    assert sale.commission.payer == nil
    assert Property.estimated_commission(sale) == 900_000

    assert {:error, changeset} =
             Properties.create_property(
               scope,
               Map.merge(@address, %{
                 "name" => "Chalet",
                 "mode" => "sale",
                 "sale_price" => "300000",
                 "commission" => %{"kind" => "months", "value" => "1"}
               })
             )

    assert %{commission: %{kind: [_]}} = errors_on(changeset)
  end

  test "a room can override the property's requirements and commission" do
    scope = user_scope_fixture()

    {:ok, property} =
      Properties.create_property(
        scope,
        Map.merge(@address, %{
          "name" => "Piso compartido",
          "mode" => "rooms",
          "requirements" => %{"payslips" => "1"},
          "commission" => %{"kind" => "months", "value" => "1"},
          "rooms" => %{
            "0" => %{"name" => "Sur", "rent" => "400"},
            "1" => %{
              "name" => "Norte",
              "rent" => "500",
              "custom_terms" => "true",
              "requirements" => %{"guarantee" => "true"},
              "commission" => %{"kind" => "fixed", "value" => "100"}
            }
          }
        })
      )

    [south, north] = property.rooms

    assert {%{payslips: 1}, %{kind: :months}, 40_000} = Property.terms(property, south)

    assert {%{payslips: nil, guarantee: true}, %{kind: :fixed}, 50_000} =
             Property.terms(property, north)

    assert Property.estimated_commission(property, south) == 40_000
    assert Property.estimated_commission(property, north) == 10_000
    assert Property.estimated_commission(property) == 50_000
  end

  test "rejects discriminatory free-text requirements" do
    changeset = Requirements.changeset(%Requirements{}, %{"other" => "Sin niños pequeños"})
    assert %{other: ["no puede incluir criterios discriminatorios"]} = errors_on(changeset)

    changeset =
      Requirements.changeset(%Requirements{}, %{"other" => "Empadronarse en la vivienda"})

    assert changeset.valid?
  end
end
