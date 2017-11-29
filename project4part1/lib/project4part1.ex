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
    {_, args, _} = OptionParser.parse(args)
    port = 6666
    if Enum.at(args, 0) == "server" do
      Logger.debug "Starting as Server"
      Server.start_link(port)
    else

      server_ip = parse_ip(Enum.at(args, 1))
      mode = Enum.at(args, 2)
      if mode == "i" do
        Logger.debug "Starting as Interactive Client"
        Client.start_link(server_ip, port)
      else
        user_count = Enum.at(args, 3) |> String.to_integer
        Client.simulate(server_ip, port, user_count)
      end
    end
  end
  defp parse_ip(str) do
    # convert input string 127.0.0.1 to tuple of integers like {127, 0, 0, 1}
    [a, b, c, d] = String.split(str, ".")
    {String.to_integer(a), String.to_integer(b), String.to_integer(c), String.to_integer(d)}
  end
end
