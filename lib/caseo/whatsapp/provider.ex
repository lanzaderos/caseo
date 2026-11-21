defmodule Caseo.Whatsapp.Provider do
  @moduledoc """
  What Caseo needs from a WhatsApp provider. whatsmeow is the first
  implementation; the official Cloud API will be the second.

  Providers receive the owner's `Caseo.Whatsapp.Account` and never return
  provider-specific structures: incoming events are normalized to the map
  described by `t:incoming/0`.
  """

  alias Caseo.Whatsapp.Account

  @typedoc "Link state of the account's number."
  @type status :: %{linked: boolean(), phone: String.t() | nil}

  @typedoc """
  A normalized incoming event. `contact_phone` is E.164 (`+34…`); `from_me`
  marks messages the owner sent from their phone.
  """
  @type incoming :: %{
          external_id: String.t(),
          contact_phone: String.t(),
          contact_name: String.t() | nil,
          from_me: boolean(),
          type: atom(),
          body: String.t() | nil,
          sent_at: DateTime.t()
        }

  @doc "Starts linking the number (e.g. a QR session) if it is not linked."
  @callback connect(Account.t()) :: {:ok, status()} | {:error, term()}

  @callback status(Account.t()) :: {:ok, status()} | {:error, term()}

  @doc "The current linking QR code as a PNG, or `:none` when there is none."
  @callback qr_image(Account.t()) :: {:ok, binary()} | :none | {:error, term()}

  @callback send_text(Account.t(), phone :: String.t(), text :: String.t()) ::
              {:ok, %{external_id: String.t(), sent_at: DateTime.t()}} | {:error, term()}

  @callback logout(Account.t()) :: :ok | {:error, term()}

  @doc """
  Authenticates and parses a webhook call. Returns the provider's session id
  and the normalized message, or `:ignore` for events Caseo does not store.
  """
  @callback parse_event(headers :: [{String.t(), String.t()}], params :: map()) ::
              {:ok, session_id :: String.t(), incoming()} | :ignore | {:error, :unauthorized}
end
