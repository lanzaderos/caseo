defmodule CaseoWeb.UserSessionController do
  use CaseoWeb, :controller

  alias Caseo.Accounts
  alias Caseo.Accounts.SecondFactor
  alias CaseoWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) when is_binary(token) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        finish_primary_login(conn, user, :magic_link, user_params, info)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}, info)
       when is_binary(email) and is_binary(password) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      finish_primary_login(conn, user, :password, user_params, info)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  defp create(conn, _params, _info), do: redirect(conn, to: ~p"/users/log-in")

  defp finish_primary_login(conn, user, method, params, info) do
    case SecondFactor.start_login(user, method) do
      {:session, token} ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.finish_login(user, token, params)

      {:challenge, challenge} ->
        UserAuth.begin_second_factor(conn, challenge, params)

      {:error, _} ->
        redirect(conn, to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user

    with true <- Accounts.sudo_mode?(user),
         {:ok, {_user, expired_tokens}} <- Accounts.update_user_password(user, user_params) do
      UserAuth.disconnect_sessions(expired_tokens)

      conn
      |> put_session(:user_return_to, ~p"/users/settings")
      |> create(params, "Password updated successfully!")
    else
      false ->
        conn
        |> put_flash(:error, "Sign in again to change your password.")
        |> redirect(to: ~p"/users/log-in")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "The password could not be updated.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
