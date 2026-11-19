defmodule CaseoWeb.PageController do
  use CaseoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
