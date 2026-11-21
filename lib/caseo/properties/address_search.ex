defmodule Caseo.Properties.AddressSearch do
  @moduledoc "Looks up Spanish postal addresses in the IGN CartoCiudad geocoder."

  @endpoint "https://www.cartociudad.es/geocoder/api/geocoder/candidates"

  def search(query) when is_binary(query) do
    query = String.trim(query)

    if String.length(query) in 4..160 do
      fetch_candidates(query)
    else
      {:ok, []}
    end
  end

  def search(_query), do: {:ok, []}

  defp fetch_candidates(query) do
    options =
      [url: @endpoint, params: [q: query, limit: 12], receive_timeout: 3_000, retry: false]
      |> Keyword.merge(Application.get_env(:caseo, __MODULE__, []))

    case Req.get(options) do
      {:ok, %Req.Response{status: 200, body: candidates}} when is_list(candidates) ->
        results = candidates |> Enum.flat_map(&postal_candidate/1) |> Enum.uniq() |> Enum.take(6)
        {:ok, results}

      _ ->
        {:error, :unavailable}
    end
  end

  defguardp coordinate?(value, min, max)
            when is_number(value) and value >= min and value <= max

  defp postal_candidate(
         %{
           "type" => "portal",
           "address" => address,
           "muni" => municipality,
           "province" => province,
           "lat" => latitude,
           "lng" => longitude
         } = candidate
       )
       when is_binary(address) and is_binary(municipality) and is_binary(province) and
              coordinate?(latitude, -90, 90) and coordinate?(longitude, -180, 180) do
    [street | _] = String.split(address, ", ", parts: 2)
    postal_code = Map.get(candidate, "postalCode")

    [
      %{
        street: street,
        municipality: municipality,
        province: province,
        postal_code: if(is_binary(postal_code), do: postal_code, else: ""),
        latitude: latitude,
        longitude: longitude
      }
    ]
  end

  defp postal_candidate(_candidate), do: []
end
