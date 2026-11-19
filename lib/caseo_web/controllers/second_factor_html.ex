defmodule CaseoWeb.SecondFactorHTML do
  use CaseoWeb, :html

  embed_templates "second_factor_html/*"

  defp totp_uri(email, secret) do
    label = URI.encode(email, &URI.char_unreserved?/1)
    params = URI.encode_query(issuer: "Caseo", secret: secret)

    "otpauth://totp/Caseo:#{label}?#{params}"
  end
end
