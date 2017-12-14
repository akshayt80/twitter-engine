defmodule Project4part2Web.PageController do
  use Project4part2Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
