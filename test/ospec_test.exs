defmodule OspecTest do
  use ExUnit.Case
  doctest Ospec

  import Ospec

  describe "Ospec.new/0" do
    test "creates a new spec" do
      assert %Ospec{
               route: nil,
               input: nil,
               output: nil
             } == new()
    end
  end

  describe "Ospec.route/3" do
    test "sets the route method and path" do
      spec =
        new()
        |> route(:get, "/test")

      assert spec.route == {:get, "/test"}
    end

    test "raises error for invalid method" do
      assert_raise Zoi.ParseError, fn ->
        new()
        |> route(:invalid, "/test")
      end
    end
  end

  describe "Ospec.input/2" do
    test "sets input with query schema" do
      query_schema = Zoi.map(%{page: Zoi.integer()})

      spec =
        new()
        |> input(query: query_schema)

      assert spec.input[:query] == query_schema
    end

    test "sets input with params schema" do
      params_schema = Zoi.map(%{id: Zoi.integer()})

      spec =
        new()
        |> input(params: params_schema)

      assert spec.input[:params] == params_schema
    end

    test "sets input with body schema" do
      body_schema = Zoi.map(%{name: Zoi.string()})

      spec =
        new()
        |> input(body: body_schema)

      assert spec.input[:body] == body_schema
    end

    test "sets input with multiple sources" do
      params_schema = Zoi.map(%{id: Zoi.integer()})
      query_schema = Zoi.map(%{include: Zoi.string()})
      body_schema = Zoi.map(%{name: Zoi.string()})

      spec =
        new()
        |> input(params: params_schema, query: query_schema, body: body_schema)

      assert spec.input[:params] == params_schema
      assert spec.input[:query] == query_schema
      assert spec.input[:body] == body_schema
    end

    test "raises error for invalid input schema" do
      assert_raise Zoi.ParseError, fn ->
        new()
        |> input(query: Zoi.integer())
      end
    end
  end

  describe "Ospec.output/2" do
    test "sets map output schema" do
      output_schema = Zoi.map(%{id: Zoi.integer(), name: Zoi.string()})

      spec =
        new()
        |> output(output_schema)

      assert spec.output == output_schema
    end

    test "sets array output schema" do
      user_schema = Zoi.map(%{id: Zoi.integer(), name: Zoi.string()})
      output_schema = Zoi.array(user_schema)

      spec =
        new()
        |> output(output_schema)

      assert spec.output == output_schema
    end
  end
end
