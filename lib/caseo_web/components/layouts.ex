defmodule CaseoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CaseoWeb, :html

  alias Phoenix.LiveView.Rendered

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Wraps page content in the shared full-height gradient and renders flash messages.

  The default layout centers account and authentication content and includes
  a link back to the home page. Pass `wide` for the landing page layout.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :wide, :boolean, default: false, doc: "uses the wider layout for the landing page"

  slot :inner_block, required: true

  @spec app(map()) :: Rendered.t()
  def app(assigns) do
    ~H"""
    <%= if @wide do %>
      <main class="page-gradient landing-page relative isolate grid min-h-dvh items-center overflow-hidden px-5 py-12 sm:px-10 sm:py-16 lg:px-14 lg:py-24">
        <div class="mx-auto w-full max-w-7xl">
          {render_slot(@inner_block)}
        </div>
      </main>
    <% else %>
      <main class="page-gradient min-h-dvh px-5 py-6 sm:px-8 sm:py-10">
        <div class="mx-auto max-w-2xl">
          <nav class="mb-8 sm:mb-12" aria-label={gettext("Home")}>
            <.link
              href={~p"/"}
              class="btn btn-ghost landing-glass-panel rounded-full px-4"
            >
              <.icon name="hero-arrow-left" class="size-4" /> Caseo
            </.link>
          </nav>
          <div class="account-content space-y-6">
            {render_slot(@inner_block)}
          </div>
        </div>
      </main>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders flash messages and LiveView connection error notices.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(map()) :: Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  @spec theme_toggle(map()) :: Rendered.t()
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        type="button"
        aria-label={gettext("System theme")}
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        type="button"
        aria-label={gettext("Light theme")}
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        type="button"
        aria-label={gettext("Dark theme")}
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
