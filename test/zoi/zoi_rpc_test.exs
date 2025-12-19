defmodule Zoi.RPCTest do
  use ExUnit.Case
  doctest Zoi.RPC

  import Zoi.RPC

  describe "Zoi.RPC.new/0" do
    test "creates a new RPC schema" do
      assert %Zoi.RPC{
               route: %{method: :get, path: "/"},
               input: nil,
               output: nil,
               handler: nil
             } == new()
    end
  end

  describe "Zoi.RPC.route/2" do
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

  describe "Zoi.RPC.input/2" do
    test "sets input with query schema" do
      query_schema = Zoi.object(%{page: Zoi.integer()})

      rpc_schema =
        new()
        |> input(query: query_schema)

      assert rpc_schema.input[:query] == query_schema
    end

    test "sets input with params schema" do
      params_schema = Zoi.object(%{id: Zoi.integer()})

      rpc_schema =
        new()
        |> input(params: params_schema)

      assert rpc_schema.input[:params] == params_schema
    end

    test "sets input with body schema" do
      body_schema = Zoi.object(%{name: Zoi.string()})

      rpc_schema =
        new()
        |> input(body: body_schema)

      assert rpc_schema.input[:body] == body_schema
    end

    test "sets input with multiple sources" do
      params_schema = Zoi.object(%{id: Zoi.integer()})
      query_schema = Zoi.object(%{include: Zoi.string()})
      body_schema = Zoi.object(%{name: Zoi.string()})

      rpc_schema =
        new()
        |> input(params: params_schema, query: query_schema, body: body_schema)

      assert rpc_schema.input[:params] == params_schema
      assert rpc_schema.input[:query] == query_schema
      assert rpc_schema.input[:body] == body_schema
    end

    test "raises error for invalid input schema" do
      assert_raise Zoi.ParseError, fn ->
        new()
        |> input(query: Zoi.integer())
      end
    end
  end

  describe "Zoi.RPC.output/2" do
    test "sets output schema" do
      output_schema = Zoi.object(%{id: Zoi.integer(), name: Zoi.string()})

      rpc_schema =
        new()
        |> output(output_schema)

      assert rpc_schema.output == output_schema
    end

    test "raises error for invalid output schema" do
      assert_raise Zoi.ParseError, fn ->
        new()
        |> output("not a schema")
      end
    end
  end

  describe "Zoi.RPC.handler/2" do
    test "sets handler function" do
      handler_fn = fn _input, _conn -> {:ok, %{}} end

      rpc_schema =
        new()
        |> handler(handler_fn)

      assert rpc_schema.handler == handler_fn
    end

    test "raises error for handler with wrong arity" do
      assert_raise Zoi.ParseError, fn ->
        new()
        |> handler(fn _input -> {:ok, %{}} end)
      end
    end

    test "raises error for non-function handler" do
      assert_raise Zoi.ParseError, fn ->
        new()
        |> handler("not a function")
      end
    end
  end
end
