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
      # Connect to server
      if mode == "i" do
        Logger.debug "Establishing Server connection"
        {:ok, socket} = :gen_tcp.connect(server_ip, port, [:binary, {:active, false},{:packet, 0}])
        Logger.debug "Server Connection Established"
        Logger.debug "Starting as Interactive Client"
        Client.start_link(socket)
      else
        user_count = Enum.at(args, 3) |> String.to_integer
        subprocess_count = Enum.at(args, 4) |> String.to_integer
        for _ <- 1..subprocess_count do
          Logger.debug "Establishing Server connection"
          {:ok, socket} = :gen_tcp.connect(server_ip, port, [:binary, {:active, false},{:packet, 0}])
          Logger.debug "Server Connection Established"
          spawn fn -> Client.simulate(socket, user_count) end
        end
      end
    end
    keep_alive()
  end
  def keep_alive() do
      :timer.sleep 10000
      keep_alive()
  end
  defp parse_ip(str) do
    # convert input string 127.0.0.1 to tuple of integers like {127, 0, 0, 1}
    [a, b, c, d] = String.split(str, ".")
    {String.to_integer(a), String.to_integer(b), String.to_integer(c), String.to_integer(d)}
  end
end
