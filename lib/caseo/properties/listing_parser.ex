defmodule Caseo.Properties.ListingParser do
  @moduledoc """
  Interprets the raw text of an Idealista listing as property form params.

  Everything is a best guess the owner reviews in the preview: fields that are
  not found are left empty for the owner to complete.
  """

  @months ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
  @date "(\\d{1,2}) de (#{Enum.join(@months, "|")})(?: de (\\d{4}))?"

  @doc "Returns property params (string keys) for `Caseo.Properties.Property.changeset/2`."
  @spec to_params(map(), Date.t()) :: map()
  def to_params(raw, today \\ Date.utc_today()) do
    text = Enum.join([raw["title"], raw["price"], raw["description"]] ++ details(raw), "\n")
    price = amount(raw["price"])

    offer =
      %{}
      |> put("available_on", available_on(text, today))
      |> put("available_until", date(text, ~r/hasta\s+(?:el\s+)?#{@date}/iu, today))
      |> put(
        "minimum_months",
        months(text, ~r/estancia\s+m[ií]nima(?:\s+de)?\s+(\d{1,2})\s+mes/iu)
      )
      |> put(
        "maximum_months",
        months(text, ~r/estancia\s+m[aá]xima(?:\s+de)?\s+(\d{1,2})\s+mes/iu)
      )
      |> put_term(text)
      |> put_students(text)

    %{"name" => raw["title"], "description" => raw["description"]}
    |> put("amenities", amenities(raw))
    |> Map.merge(address(raw["address"] || []))
    |> Map.merge(mode_params(mode(raw), price, offer))
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc "Usable floor area in m², or `nil`."
  @spec area(map()) :: pos_integer() | nil
  def area(raw) do
    # Flats: "117 m²" / "117 m² construidos". Rooms: "Habitación en piso de 133 m²".
    Enum.find_value(details(raw), fn feature ->
      case Regex.run(
             ~r/^(?:habitaci[oó]n en piso de\s+)?(\d{1,3}(?:\.\d{3})*|\d+)\s*m²/iu,
             feature
           ) do
        [_, number] -> number |> String.replace(".", "") |> String.to_integer()
        nil -> nil
      end
    end)
  end

  defp mode(raw) do
    cond do
      raw["title"] =~ ~r/^(?:alquiler de\s+)?habitaci[oó]n\b/iu -> :rooms
      raw["price"] =~ ~r/€\s*\/\s*mes/u -> :rental
      true -> :sale
    end
  end

  defp mode_params(:rooms, price, offer) do
    room = offer |> Map.put("name", "Habitación") |> put("rent", price)
    %{"mode" => "rooms", "rooms" => %{"0" => room}}
  end

  defp mode_params(:rental, price, offer),
    do: offer |> Map.put("mode", "rental") |> put("rent", price)

  defp mode_params(:sale, price, _offer), do: put(%{"mode" => "sale"}, "sale_price", price)

  defp put_term(offer, text) do
    if text =~ ~r/temporada|alquiler\s+temporal|corta\s+estancia|estancia\s+m[ií]nima/iu,
      do: Map.put(offer, "rental_term", "temporary"),
      else: offer
  end

  defp put_students(offer, text) do
    if text =~ ~r/estudiant/iu do
      offer
      |> Map.put("for_students", "true")
      |> put("academic_year", academic_year(text))
    else
      offer
    end
  end

  defp academic_year(text) do
    case Regex.run(~r/curso\s+(20\d{2})\s*[\/\-–]\s*(?:20)?(\d{2})\b/iu, text) do
      [_, start, finish] -> "#{start}–20#{finish}"
      nil -> nil
    end
  end

  defp amount(price) when is_binary(price) do
    case Regex.run(~r/(\d{1,3}(?:\.\d{3})*|\d+)(?:,(\d{1,2}))?\s*€/u, price) do
      [_, euros | cents] ->
        String.replace(euros, ".", "") <> Enum.map_join(cents, &",#{&1}")

      nil ->
        nil
    end
  end

  defp amount(_price), do: nil

  defp date(text, regex, today) do
    with [_, day, month | year] <- Regex.run(regex, text),
         month = Enum.find_index(@months, &(&1 == String.downcase(month))) + 1,
         {:ok, date} <- build_date(year, month, String.to_integer(day), today) do
      Date.to_iso8601(date)
    else
      _ -> nil
    end
  end

  # Idealista writes "Disponible a partir del 1 de febrero", "DISPONIBLE DEL
  # 01/02/2027" or "Ya disponible".
  defp available_on(text, today) do
    from = "disponible\\s+(?:a partir del?|desde(?: el)?|del?)\\s+"
    numeric = Regex.run(~r/#{from}(\d{1,2})\/(\d{1,2})\/(\d{4})/iu, text)

    cond do
      written = date(text, ~r/#{from}#{@date}/iu, today) -> written
      numeric -> numeric_date(numeric)
      text =~ ~r/\bya disponible\b/iu -> Date.to_iso8601(today)
      true -> nil
    end
  end

  defp numeric_date([_, day, month, year]) do
    case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      {:ok, date} -> Date.to_iso8601(date)
      {:error, _} -> nil
    end
  end

  # Without a year, the listing means the next occurrence of that day.
  defp build_date([year], month, day, _today), do: Date.new(String.to_integer(year), month, day)

  defp build_date([], month, day, today) do
    with {:ok, date} <- Date.new(today.year, month, day) do
      if Date.compare(date, today) == :lt,
        do: Date.new(today.year + 1, month, day),
        else: {:ok, date}
    end
  end

  defp months(text, regex) do
    case Regex.run(regex, text) do
      [_, number] -> number
      nil -> nil
    end
  end

  # `#headerMap` goes from specific to general: street, neighbourhood,
  # district, municipality and "area, province". The street is missing when
  # the advertiser hides it. Idealista publishes no postal code.
  defp address(lines) when length(lines) >= 2 do
    [first | _] = lines
    province = lines |> List.last() |> String.split(", ") |> List.last()
    street? = length(lines) > 2 and not (first =~ ~r/^(barrio|distrito|zona|urbanizaci[oó]n)\b/iu)

    %{"municipality" => Enum.at(lines, -2), "province" => province}
    |> put("street", if(street?, do: first))
  end

  defp address(_lines), do: %{}

  defp amenities(raw) do
    case raw["details"] || [] do
      [] -> nil
      details -> details |> Enum.join("\n") |> String.slice(0, 5_000)
    end
  end

  defp details(raw), do: (raw["features"] || []) ++ (raw["details"] || [])

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
