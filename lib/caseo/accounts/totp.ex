defmodule Caseo.Accounts.TOTP do
  @moduledoc """
  RFC 6238 with six digits, HMAC-SHA-1 and 30-second steps.
  """
  import Bitwise

  def matching_step(secret, code, last_step, now) when byte_size(code) == 6 do
    step = div(DateTime.to_unix(now), 30)

    Enum.find([step, step - 1, step + 1], fn candidate ->
      candidate > (last_step || -1) and
        Plug.Crypto.secure_compare(code(secret, candidate), code)
    end)
  end

  def matching_step(_secret, _code, _last_step, _now), do: nil

  def code(secret, step) do
    digest = :crypto.mac(:hmac, :sha, secret, <<step::unsigned-64>>)
    offset = band(:binary.last(digest), 15)
    <<_::binary-size(^offset), _::1, value::31, _::binary>> = digest

    value
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end
end
