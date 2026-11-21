defmodule Caseo.Properties.ListingImages do
  @moduledoc """
  Copies listing images the owner selected into the property's gallery.
  Callers pass only URLs already validated against the import.
  """

  require Logger

  alias Caseo.Properties.Photos

  @doc "Downloads each image and adds it to the gallery. Returns how many were added."
  @spec copy(Caseo.Accounts.Scope.t(), pos_integer(), [String.t()]) :: non_neg_integer()
  def copy(scope, property_id, urls) do
    urls
    |> Enum.take(Photos.image_limit())
    |> Enum.count(fn url ->
      with {:ok, data} <- download(url),
           {:ok, _photo} <- Photos.add(scope, property_id, nil, data) do
        true
      else
        error ->
          Logger.info("listing image not copied: #{inspect(error)}")
          false
      end
    end)
  end

  # ponytail: sequential downloads; parallelise if imports with many photos get slow.
  defp download(url) do
    options =
      [url: url, receive_timeout: 10_000, retry: false, redirect: false, decode_body: false]
      |> Keyword.merge(Application.get_env(:caseo, __MODULE__, []))

    case Req.get(options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        if byte_size(body) <= Photos.file_size_limit(),
          do: {:ok, body},
          else: {:error, :too_large}

      other ->
        {:error, other}
    end
  end
end
