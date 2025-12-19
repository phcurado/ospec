defmodule Zoi.RPCTest do
  use ExUnit.Case
  doctest Zoi.RPC

  import Zoi.RPC

  describe "Zoi.RPC.new/0" do
    test "creates a new RPC schema" do
      rpc_schema = new()
      assert rpc_schema.__struct__ == Zoi.RPC
    end
  end

  describe "Zoi.RPC.route/3" do
    test "sets the route method and path" do
      rpc_schema =
        new()
        |> route(method: :get, path: "/test")

      assert rpc_schema.route[:method] == :get
      assert rpc_schema.route[:path] == "/test"
    end

    test "raises error for invalid method" do
      error =
        """
        Parsing error:

        invalid enum value: expected one of get, post, put, delete, at method
        """

      assert_raise Zoi.ParseError, error, fn ->
        new()
        |> route(method: :invalid, path: "/test")
      end
    end
  end
end
