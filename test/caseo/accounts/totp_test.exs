defmodule Caseo.Accounts.TOTPTest do
  use ExUnit.Case, async: true

  alias Caseo.Accounts.TOTP

  test "matches the last six digits of RFC 6238 SHA-1 test vectors" do
    secret = "12345678901234567890"
    assert TOTP.code(secret, div(59, 30)) == "287082"
    assert TOTP.code(secret, div(1_234_567_890, 30)) == "005924"
    assert TOTP.code(secret, div(20_000_000_000, 30)) == "353130"
  end
end
