defmodule Caseo.Properties.ListingParserTest do
  use ExUnit.Case, async: true

  alias Caseo.Properties.ListingParser

  @today ~D[2026-11-21]

  # Read from a real listing: https://www.idealista.com/inmueble/112450146/
  @sale %{
    "title" => "Piso en venta en Calle del Duque de Sesto",
    "price" => "1.500.000 €",
    "location" => "Goya, Madrid",
    "features" => ["117 m²", "3 hab.", "5ª planta exterior con ascensor"],
    "details" => ["117 m² construidos", "3 habitaciones", "3 baños", "Terraza"],
    "address" => [
      "Calle del Duque de Sesto",
      "Barrio Goya",
      "Distrito Barrio de Salamanca",
      "Madrid",
      "Madrid capital, Madrid"
    ]
  }

  test "reads a real sale listing with its address" do
    assert ListingParser.to_params(@sale, @today) == %{
             "name" => "Piso en venta en Calle del Duque de Sesto",
             "mode" => "sale",
             "sale_price" => "1500000",
             "street" => "Calle del Duque de Sesto",
             "municipality" => "Madrid",
             "province" => "Madrid",
             "amenities" => "117 m² construidos\n3 habitaciones\n3 baños\nTerraza"
           }

    assert ListingParser.area(@sale) == 117
  end

  test "reads a long-term rental and omits a hidden street" do
    params =
      ListingParser.to_params(
        %{
          "title" => "Piso en alquiler en Ruzafa",
          "price" => "1.250,50 €/mes",
          "description" => "Piso luminoso. Disponible a partir del 1 de febrero.",
          "address" => ["Barrio Ruzafa", "Distrito Ensanche", "València", "València, Valencia"]
        },
        @today
      )

    assert params["mode"] == "rental"
    assert params["rent"] == "1250,50"
    assert params["available_on"] == "2027-02-01"
    assert params["municipality"] == "València"
    assert params["province"] == "Valencia"
    refute Map.has_key?(params, "street")
    refute Map.has_key?(params, "rental_term")
  end

  test "reads a temporary room for students with dates and stay limits" do
    params =
      ListingParser.to_params(
        %{
          "title" => "Habitación en calle de Bravo Murillo",
          "price" => "450 €/mes",
          "description" =>
            "Alquiler de temporada para estudiantes, curso 2026/27. Disponible desde el " <>
              "1 de septiembre de 2026 hasta el 30 de junio de 2027. Estancia mínima de 3 meses."
        },
        @today
      )

    assert %{"mode" => "rooms", "rooms" => %{"0" => room}} = params

    assert room == %{
             "name" => "Habitación",
             "rent" => "450",
             "rental_term" => "temporary",
             "for_students" => "true",
             "academic_year" => "2026–2027",
             "available_on" => "2026-09-01",
             "available_until" => "2027-06-30",
             "minimum_months" => "3"
           }
  end

  # Read from a real listing: https://www.idealista.com/inmueble/113130104/
  test "reads a real room listing with its stay limits" do
    raw = %{
      "title" => "Alquiler de habitación en Bravo Murillo, 126",
      "price" => "790 €/mes",
      "location" => "Cuatro Caminos, Madrid",
      "description" => "Alquiler de habitación en una de las zonas más demandadas de Madrid.",
      "features" => ["6 hab.", "6 chicos/as", "6", "No se puede fumar"],
      "details" => [
        "Alguien entre 18 y 35 años",
        "Estancia mínima de 1 mes",
        "Estancia máxima de 12 meses",
        "Ya disponible",
        "Habitación en piso de 133 m²",
        "Tamaño de la habitación: 12 m²",
        "Estudian/ Trabajan"
      ],
      "address" => [
        "Bravo Murillo, 126",
        "Barrio Cuatro Caminos",
        "Distrito Tetuán",
        "Madrid",
        "Madrid capital, Madrid"
      ]
    }

    params = ListingParser.to_params(raw, @today)

    assert %{"mode" => "rooms", "street" => "Bravo Murillo, 126", "rooms" => %{"0" => room}} =
             params

    assert room == %{
             "name" => "Habitación",
             "rent" => "790",
             "rental_term" => "temporary",
             "available_on" => "2026-11-21",
             "minimum_months" => "1",
             "maximum_months" => "12"
           }

    assert ListingParser.area(raw) == 133
  end

  # Read from a real listing: https://www.idealista.com/inmueble/112382792/
  test "reads a real studio for students with a numeric availability date" do
    raw = %{
      "title" => "Alquiler de estudio en Calle de las Minas, 23",
      "price" => "950 €/mes",
      "description" =>
        "Estudio situado en calle de Minas, ideal para estudiantes que buscan vivir en una " <>
          "zona céntrica. DISPONIBLE DEL 01/02/2027La vivienda ofrece un espacio funcional.",
      "features" => ["30 m²", "3ª planta exterior sin ascensor"],
      "address" => [
        "Calle de las Minas, 23",
        "Barrio Malasaña-Universidad",
        "Distrito Centro",
        "Madrid",
        "Madrid capital, Madrid"
      ]
    }

    assert %{
             "mode" => "rental",
             "rent" => "950",
             "for_students" => "true",
             "available_on" => "2027-02-01",
             "street" => "Calle de las Minas, 23"
           } = ListingParser.to_params(raw, @today)

    assert ListingParser.area(raw) == 30
  end

  test "leaves out what the listing does not include" do
    assert ListingParser.to_params(%{"title" => "Estudio", "price" => "A consultar"}, @today) ==
             %{"name" => "Estudio", "mode" => "sale"}

    assert ListingParser.area(%{}) == nil
  end
end
