defmodule ZoiRPCTest do
  use ExUnit.Case
  doctest ZoiRPC

  test "greets the world" do
    assert ZoiRPC.hello() == :world
  end
end
