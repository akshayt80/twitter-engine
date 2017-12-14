defmodule PhoenixClientTest do
  use ExUnit.Case
  doctest PhoenixClient

  test "greets the world" do
    assert PhoenixClient.hello() == :world
  end
end
