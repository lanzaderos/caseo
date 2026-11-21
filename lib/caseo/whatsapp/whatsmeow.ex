defmodule Caseo.Whatsapp.Whatsmeow do
  @moduledoc """
  `Caseo.Whatsapp.Provider` backed by the whatsmeow sidecar (`whatsmeow/`).
  Each account is one sidecar session. Configure `:base_url` and `:token`.
  """

  @behaviour Caseo.Whatsapp.Provider

  alias Caseo.Leads.Lead

  @impl true
  def connect(account) do
    with {:ok, body} <- request(:post, account, "/connect"), do: {:ok, status_from(body)}
  end

  @impl true
  def status(account) do
    with {:ok, body} <- request(:get, account, "/status"), do: {:ok, status_from(body)}
  end

  @impl true
  def qr_image(account) do
    case Req.request(options(account, :get, "/qr.png", decode_body: false)) do
      {:ok, %Req.Response{status: 200, body: png}} -> {:ok, png}
      {:ok, %Req.Response{status: 204}} -> :none
      other -> {:error, error(other)}
    end
  end

  @impl true
  def send_text(account, phone, text) do
    body = %{to: String.trim_leading(phone, "+"), text: text}

    with {:ok, %{"id" => id, "timestamp" => timestamp}} <-
           request(:post, account, "/send", json: body, receive_timeout: 30_000),
         {:ok, sent_at, _offset} <- DateTime.from_iso8601(timestamp) do
      {:ok, %{external_id: id, sent_at: DateTime.truncate(sent_at, :second)}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unexpected_response}
    end
  end

  @impl true
  def logout(account) do
    with {:ok, _body} <- request(:post, account, "/logout"), do: :ok
  end

  @impl true
  def parse_event(headers, params) do
    expected = "Bearer " <> token()

    case List.keyfind(headers, "authorization", 0) do
      {_, value} when byte_size(value) == byte_size(expected) ->
        if Plug.Crypto.secure_compare(value, expected),
          do: parse_message(params),
          else: {:error, :unauthorized}

      _ ->
        {:error, :unauthorized}
    end
  end

  defp parse_message(
         %{
           "session" => session,
           "id" => id,
           "chat" => chat,
           "from_me" => from_me,
           "timestamp" => timestamp
         } = params
       )
       when is_binary(session) and is_binary(id) and is_binary(chat) and chat != "" do
    case DateTime.from_iso8601(timestamp) do
      {:ok, sent_at, _offset} ->
        {:ok, session,
         %{
           external_id: id,
           contact_phone: Lead.normalize_phone("+" <> chat),
           # The push name is the sender's: only use it for the contact when they wrote.
           contact_name: if(from_me, do: nil, else: blank_to_nil(params["push_name"])),
           from_me: from_me == true,
           type: type(params["type"]),
           body: blank_to_nil(params["text"]),
           sent_at: DateTime.truncate(sent_at, :second)
         }}

      _invalid ->
        :ignore
    end
  end

  defp parse_message(_params), do: :ignore

  @types Map.new(Caseo.Whatsapp.Message.types(), &{Atom.to_string(&1), &1})
  defp type(type), do: Map.get(@types, type, :other)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.slice(value, 0, 10_000)
  defp blank_to_nil(_value), do: nil

  defp status_from(body) do
    phone = if body["jid"] not in [nil, ""], do: "+" <> body["jid"]
    %{linked: body["logged_in"] == true, phone: phone}
  end

  defp request(method, account, path, extra \\ []) do
    case Req.request(options(account, method, path, extra)) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, if(is_map(body), do: body, else: %{})}

      other ->
        {:error, error(other)}
    end
  end

  defp error({:ok, %Req.Response{status: 429}}), do: :rate_limited
  defp error({:ok, %Req.Response{status: 503}}), do: :not_linked
  defp error({:ok, %Req.Response{status: status}}), do: {:http, status}
  defp error({:error, _exception}), do: :unavailable

  defp options(account, method, path, extra) do
    config = Application.get_env(:caseo, __MODULE__, [])

    [
      method: method,
      base_url: Keyword.fetch!(config, :base_url),
      url: "/sessions/#{account.session_id}" <> path,
      auth: {:bearer, token()},
      receive_timeout: 10_000,
      retry: false
    ]
    |> Keyword.merge(Keyword.drop(config, [:base_url, :token]))
    |> Keyword.merge(extra)
  end

  defp token, do: :caseo |> Application.get_env(__MODULE__, []) |> Keyword.fetch!(:token)
end
