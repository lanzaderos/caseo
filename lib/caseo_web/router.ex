defmodule CaseoWeb.Router do
  use CaseoWeb, :router

  import CaseoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CaseoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CaseoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", CaseoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:caseo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CaseoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", CaseoWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{CaseoWeb.UserAuth, :require_authenticated}] do
      live "/inmuebles", PropertyLive.Index, :index
      live "/inmuebles/nuevo", PropertyLive.Form, :new
      live "/inmuebles/:id/editar", PropertyLive.Form, :edit
      live "/inmuebles/:id/habitaciones/:room_id/fotos", PropertyLive.Gallery, :room
      live "/inmuebles/:id", PropertyLive.Gallery, :property

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    get "/archivos/inmuebles/:id", PropertyPhotoController, :show

    get "/users/settings/passkeys", PasskeyController, :settings
    post "/users/settings/passkeys/options", PasskeyController, :registration_options
    post "/users/settings/passkeys", PasskeyController, :register
    patch "/users/settings/passkeys/:id", PasskeyController, :rename
    delete "/users/settings/passkeys/:id", PasskeyController, :revoke

    get "/users/settings/second-factor", SecondFactorController, :settings
    post "/users/settings/second-factor", SecondFactorController, :enable
    delete "/users/settings/second-factor", SecondFactorController, :disable
    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", CaseoWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{CaseoWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    get "/users/second-factor", SecondFactorController, :challenge
    post "/users/second-factor", SecondFactorController, :verify
    post "/users/log-in/passkey/options", PasskeyController, :authentication_options
    post "/users/log-in/passkey", PasskeyController, :authenticate
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
