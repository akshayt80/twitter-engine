defmodule Project4part1 do
  @moduledoc """
  Documentation for Project4part1.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Project4part1.hello
      :world

  """
  require Logger
  def main(args) do
    {_, [str], _} = OptionParser.parse(args)
    server_ip = parse_ip("127.0.0.1")
    port = 6666
    if str == "server" do
      Logger.debug "Starting as Server"
      Server.start_link(port)
    else
      Logger.debug "Starting as Client"
      Client.start_link(server_ip, port)
    end
  end
  defp parse_ip(str) do
    # convert input string 127.0.0.1 to tuple of integers like {127, 0, 0, 1}
    [a, b, c, d] = String.split(str, ".")
    {String.to_integer(a), String.to_integer(b), String.to_integer(c), String.to_integer(d)}
  end
end
