defmodule Caseo.Visits.BookingLink do
  @moduledoc """
  A public, revocable link through which a lead requests a visit slot. Only
  the SHA-256 hash of the token is stored.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @validity_days 7

  schema "booking_links" do
    belongs_to :interest, Caseo.Leads.Interest
    belongs_to :visit, Caseo.Visits.Visit
    field :token_hash, :binary
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a link for an interest. Returns the link and its clear token."
  @spec build(integer()) :: {t(), String.t()}
  def build(interest_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    link = %__MODULE__{
      interest_id: interest_id,
      token_hash: hash(token),
      expires_at: DateTime.utc_now(:second) |> DateTime.add(@validity_days, :day)
    }

    {link, token}
  end

  @doc "Hashes a clear token."
  @spec hash(String.t()) :: binary()
  def hash(token), do: :crypto.hash(:sha256, token)

  @doc "Whether the link still accepts a booking."
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{} = link) do
    is_nil(link.revoked_at) and is_nil(link.visit_id) and
      DateTime.compare(link.expires_at, DateTime.utc_now()) == :gt
  end
end
