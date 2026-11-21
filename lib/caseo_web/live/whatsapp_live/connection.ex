defmodule CaseoWeb.WhatsappLive.Connection do
  use CaseoWeb, :live_view

  alias Caseo.Whatsapp
  alias Caseo.Whatsapp.Account

  @poll_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Whatsapp.subscribe(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(page_title: "WhatsApp", linking: false, tick: 0)
     |> refresh()}
  end

  @impl true
  def handle_event("link", _params, socket) do
    case Whatsapp.connect(socket.assigns.current_scope) do
      {:ok, account} ->
        {:noreply,
         socket |> assign(account: account, linking: true, unavailable: false) |> poll()}

      {:error, _reason} ->
        {:noreply, assign(socket, unavailable: true)}
    end
  end

  def handle_event("unlink", _params, socket) do
    case Whatsapp.disconnect(socket.assigns.current_scope) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Número desvinculado.")
         |> assign(linking: false)
         |> refresh()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "No se pudo desvincular. Inténtalo de nuevo.")}
    end
  end

  @impl true
  def handle_info(:poll, %{assigns: %{linking: true}} = socket) do
    socket = refresh(socket)

    if Account.linked?(socket.assigns.account) do
      {:noreply, socket |> assign(linking: false) |> put_flash(:info, "WhatsApp vinculado.")}
    else
      {:noreply, socket |> update(:tick, &(&1 + 1)) |> poll()}
    end
  end

  def handle_info(:poll, socket), do: {:noreply, socket}

  def handle_info({:whatsapp_account, account}, socket),
    do: {:noreply, assign(socket, account: account)}

  def handle_info({:whatsapp_message, _message}, socket), do: {:noreply, socket}

  defp poll(socket) do
    Process.send_after(self(), :poll, @poll_ms)
    socket
  end

  defp refresh(socket) do
    case Whatsapp.refresh(socket.assigns.current_scope) do
      {:ok, account} ->
        assign(socket, account: account, unavailable: false)

      {:error, _reason} ->
        assign(socket,
          account: Whatsapp.get_account(socket.assigns.current_scope),
          unavailable: true
        )
    end
  end
end
