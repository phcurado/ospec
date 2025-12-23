defmodule Ospec.HandlerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  import Ospec.Handler

  # HTTP params have string keys, so we need coerce: true for key normalization
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

  describe "handle/4" do
    test "successful request with query params" do
      conn = conn(:get, "/users", %{"page" => "2"})

      conn =
        handle(conn, conn.params, list_users_contract(), fn input, _conn ->
          assert input.page == 2
          {:ok, [%{id: 1, name: "Alice"}]}
        end)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == [%{"id" => 1, "name" => "Alice"}]
    end

    test "successful request with path params" do
      conn = conn(:get, "/users/123", %{"id" => "123"})

      conn =
        handle(conn, conn.params, find_user_contract(), fn input, _conn ->
          assert input.id == 123
          {:ok, %{id: 123, name: "Bob"}}
        end)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"id" => 123, "name" => "Bob"}
    end

    test "successful request with body params" do
      conn = conn(:post, "/users", %{"name" => "Charlie"})

      conn =
        handle(conn, conn.params, create_user_contract(), fn input, _conn ->
          assert input.name == "Charlie"
          {:ok, %{id: 1, name: "Charlie"}}
        end)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"id" => 1, "name" => "Charlie"}
    end

    test "validation error on invalid input" do
      conn = conn(:get, "/users", %{"page" => "not_a_number"})

      conn =
        handle(conn, conn.params, list_users_contract(), fn _input, _conn ->
          {:ok, []}
        end)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "VALIDATION_ERROR"
      assert body["message"] == "Validation failed"
      assert is_map(body["data"])
    end

    test "handler returns not_found error" do
      conn = conn(:get, "/users/999", %{"id" => "999"})

      conn =
        handle(conn, conn.params, find_user_contract(), fn _input, _conn ->
          {:error, :not_found}
        end)

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "NOT_FOUND"
    end

    test "handler returns unauthorized error" do
      conn = conn(:get, "/users/1", %{"id" => "1"})

      conn =
        handle(conn, conn.params, find_user_contract(), fn _input, _conn ->
          {:error, :unauthorized}
        end)

      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "UNAUTHORIZED"
    end

    test "handler returns custom error message" do
      conn = conn(:get, "/users/1", %{"id" => "1"})

      conn =
        handle(conn, conn.params, find_user_contract(), fn _input, _conn ->
          {:error, "Something went wrong"}
        end)

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "INTERNAL_ERROR"
      assert body["message"] == "Something went wrong"
    end

    test "handler returns generic error" do
      conn = conn(:get, "/users/1", %{"id" => "1"})

      conn =
        handle(conn, conn.params, find_user_contract(), fn _input, _conn ->
          {:error, :some_unexpected_error}
        end)

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "INTERNAL_ERROR"
      assert body["message"] == "Internal server error"
    end

    test "output validation error" do
      conn = conn(:get, "/users/1", %{"id" => "1"})

      conn =
        handle(conn, conn.params, find_user_contract(), fn _input, _conn ->
          {:ok, %{invalid: "output"}}
        end)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "VALIDATION_ERROR"
    end

    test "default values are applied" do
      conn = conn(:get, "/users", %{})

      conn =
        handle(conn, conn.params, list_users_contract(), fn input, _conn ->
          assert input.page == 1
          {:ok, []}
        end)

      assert conn.status == 200
    end

    test "conn is passed to handler" do
      conn =
        conn(:get, "/users", %{})
        |> Plug.Conn.assign(:current_user, %{id: 42})

      conn =
        handle(conn, conn.params, list_users_contract(), fn _input, conn ->
          assert conn.assigns.current_user == %{id: 42}
          {:ok, []}
        end)

      assert conn.status == 200
    end
  end
end
