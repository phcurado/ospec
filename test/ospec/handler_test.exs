defmodule Ospec.HandlerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  import Ospec.Handler

  @user_schema Zoi.object(%{id: Zoi.integer(), name: Zoi.string()}, coerce: true)

  defp list_users_contract do
    Ospec.new()
    |> Ospec.route(method: :get, path: "/users")
    |> Ospec.input(query: Zoi.object(%{page: Zoi.integer() |> Zoi.default(1)}, coerce: true))
    |> Ospec.output(Zoi.array(@user_schema))
  end

  defp find_user_contract do
    Ospec.new()
    |> Ospec.route(method: :get, path: "/users/:id")
    |> Ospec.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
    |> Ospec.output(@user_schema)
  end

  defp create_user_contract do
    Ospec.new()
    |> Ospec.route(method: :post, path: "/users")
    |> Ospec.input(body: Zoi.object(%{name: Zoi.string()}, coerce: true))
    |> Ospec.output(@user_schema)
  end

  defp no_output_contract do
    Ospec.new()
    |> Ospec.route(method: :delete, path: "/users/:id")
    |> Ospec.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
  end

  defp build_conn(method, path, opts) do
    conn = conn(method, path)

    conn
    |> Map.put(:path_params, Keyword.get(opts, :path_params, %{}))
    |> Map.put(:query_params, Keyword.get(opts, :query_params, %{}))
    |> Map.put(:body_params, Keyword.get(opts, :body_params, %{}))
  end

  describe "handle/3" do
    test "successful request with query params" do
      conn = build_conn(:get, "/users", query_params: %{"page" => "2"})

      conn =
        handle(conn, list_users_contract(), fn input, _conn ->
          assert input.page == 2
          {:ok, [%{id: 1, name: "Alice"}]}
        end)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == [%{"id" => 1, "name" => "Alice"}]
    end

    test "successful request with path params" do
      conn = build_conn(:get, "/users/123", path_params: %{"id" => "123"})

      conn =
        handle(conn, find_user_contract(), fn input, _conn ->
          assert input.id == 123
          {:ok, %{id: 123, name: "Bob"}}
        end)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"id" => 123, "name" => "Bob"}
    end

    test "successful request with body params" do
      conn = build_conn(:post, "/users", body_params: %{"name" => "Charlie"})

      conn =
        handle(conn, create_user_contract(), fn input, _conn ->
          assert input.name == "Charlie"
          {:ok, %{id: 1, name: "Charlie"}}
        end)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"id" => 1, "name" => "Charlie"}
    end

    test "input sources are isolated (no key bleeding)" do
      # This test ensures query params don't leak into body validation
      conn =
        build_conn(:post, "/users",
          query_params: %{"name" => "from_query"},
          body_params: %{"name" => "from_body"}
        )

      conn =
        handle(conn, create_user_contract(), fn input, _conn ->
          # Should get body value, not query value
          assert input.name == "from_body"
          {:ok, %{id: 1, name: input.name}}
        end)

      assert conn.status == 200
    end

    test "validation error on invalid input" do
      conn = build_conn(:get, "/users", query_params: %{"page" => "not_a_number"})

      conn =
        handle(conn, list_users_contract(), fn _input, _conn ->
          {:ok, []}
        end)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "VALIDATION_ERROR"
      assert body["message"] == "Validation failed"
      assert is_map(body["data"])
    end

    test "handler returns not_found error" do
      conn = build_conn(:get, "/users/999", path_params: %{"id" => "999"})

      conn =
        handle(conn, find_user_contract(), fn _input, _conn ->
          {:error, :not_found}
        end)

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "NOT_FOUND"
    end

    test "handler returns unauthorized error" do
      conn = build_conn(:get, "/users/1", path_params: %{"id" => "1"})

      conn =
        handle(conn, find_user_contract(), fn _input, _conn ->
          {:error, :unauthorized}
        end)

      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "UNAUTHORIZED"
    end

    test "handler returns custom error message" do
      conn = build_conn(:get, "/users/1", path_params: %{"id" => "1"})

      conn =
        handle(conn, find_user_contract(), fn _input, _conn ->
          {:error, "Something went wrong"}
        end)

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "INTERNAL_ERROR"
      assert body["message"] == "Something went wrong"
    end

    test "handler returns generic error" do
      conn = build_conn(:get, "/users/1", path_params: %{"id" => "1"})

      conn =
        handle(conn, find_user_contract(), fn _input, _conn ->
          {:error, :some_unexpected_error}
        end)

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "INTERNAL_ERROR"
      assert body["message"] == "Internal server error"
    end

    test "output validation error returns 500 (server bug)" do
      conn = build_conn(:get, "/users/1", path_params: %{"id" => "1"})

      conn =
        handle(conn, find_user_contract(), fn _input, _conn ->
          {:ok, %{invalid: "output"}}
        end)

      # Output validation failure is a server bug, not a client error
      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "OUTPUT_VALIDATION_ERROR"
      assert body["message"] == "Response validation failed"
    end

    test "default values are applied" do
      conn = build_conn(:get, "/users", query_params: %{})

      conn =
        handle(conn, list_users_contract(), fn input, _conn ->
          assert input.page == 1
          {:ok, []}
        end)

      assert conn.status == 200
    end

    test "conn is passed to handler" do
      conn =
        build_conn(:get, "/users", query_params: %{})
        |> Plug.Conn.assign(:current_user, %{id: 42})

      conn =
        handle(conn, list_users_contract(), fn _input, conn ->
          assert conn.assigns.current_user == %{id: 42}
          {:ok, []}
        end)

      assert conn.status == 200
    end

    test "contract without output schema skips output validation" do
      conn = build_conn(:delete, "/users/1", path_params: %{"id" => "1"})

      conn =
        handle(conn, no_output_contract(), fn input, _conn ->
          assert input.id == 1
          {:ok, %{deleted: true}}
        end)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"deleted" => true}
    end

    test "multiple input sources combined" do
      contract =
        Ospec.new()
        |> Ospec.route(method: :put, path: "/users/:id")
        |> Ospec.input(
          params: Zoi.object(%{id: Zoi.integer()}, coerce: true),
          query: Zoi.object(%{notify: Zoi.boolean() |> Zoi.default(false)}, coerce: true),
          body: Zoi.object(%{name: Zoi.string()}, coerce: true)
        )
        |> Ospec.output(@user_schema)

      conn =
        build_conn(:put, "/users/123",
          path_params: %{"id" => "123"},
          query_params: %{"notify" => "true"},
          body_params: %{"name" => "Updated"}
        )

      conn =
        handle(conn, contract, fn input, _conn ->
          assert input.id == 123
          assert input.notify == true
          assert input.name == "Updated"
          {:ok, %{id: 123, name: "Updated"}}
        end)

      assert conn.status == 200
    end
  end
end
