defmodule Zoi.RPC.ClientTest do
  use ExUnit.Case, async: true

  alias Zoi.RPC.Client

  # Use Req.Test verification
  setup :verify_on_exit!

  defp verify_on_exit!(_context) do
    on_exit(fn -> Req.Test.verify!() end)
    :ok
  end

  describe "new/1" do
    test "creates client with base_url" do
      client = Client.new(base_url: "http://localhost:4000")

      assert client.base_url == "http://localhost:4000"
      assert client.headers == %{}
      assert client.req_options == []
    end

    test "creates client with headers" do
      client =
        Client.new(
          base_url: "http://localhost:4000",
          headers: %{"authorization" => "Bearer token"}
        )

      assert client.headers == %{"authorization" => "Bearer token"}
    end

    test "creates client with req_options" do
      client =
        Client.new(
          base_url: "http://localhost:4000",
          req_options: [receive_timeout: 5000]
        )

      assert client.req_options == [receive_timeout: 5000]
    end

    test "raises on missing base_url" do
      assert_raise Zoi.ParseError, fn ->
        Client.new([])
      end
    end
  end

  describe "call/3" do
    @user_schema Zoi.object(%{id: Zoi.integer(), name: Zoi.string()}, coerce: true)

    defp find_user_contract do
      Zoi.RPC.new()
      |> Zoi.RPC.route(method: :get, path: "/users/:id")
      |> Zoi.RPC.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
      |> Zoi.RPC.output(@user_schema)
    end

    defp create_user_contract do
      Zoi.RPC.new()
      |> Zoi.RPC.route(method: :post, path: "/users")
      |> Zoi.RPC.input(body: Zoi.object(%{name: Zoi.string()}, coerce: true))
      |> Zoi.RPC.output(@user_schema)
    end

    defp list_users_contract do
      Zoi.RPC.new()
      |> Zoi.RPC.route(method: :get, path: "/users")
      |> Zoi.RPC.input(query: Zoi.object(%{page: Zoi.integer() |> Zoi.default(1)}, coerce: true))
      |> Zoi.RPC.output(Zoi.array(@user_schema))
    end

    test "successful GET request with path params" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/users/123"

        Req.Test.json(conn, %{"id" => 123, "name" => "Alice"})
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = find_user_contract()

      assert {:ok, %{id: 123, name: "Alice"}} = Client.call(client, contract, %{id: 123})
    end

    test "successful GET request with query params" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/users"
        assert conn.query_string == "page=2"

        Req.Test.json(conn, [%{"id" => 1, "name" => "Alice"}])
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = list_users_contract()

      assert {:ok, [%{id: 1, name: "Alice"}]} = Client.call(client, contract, %{page: 2})
    end

    test "successful POST request with body" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/users"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "Bob"}

        Req.Test.json(conn, %{"id" => 1, "name" => "Bob"})
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = create_user_contract()

      assert {:ok, %{id: 1, name: "Bob"}} = Client.call(client, contract, %{name: "Bob"})
    end

    test "applies default query values" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.query_string == "page=1"

        Req.Test.json(conn, [])
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = list_users_contract()

      assert {:ok, []} = Client.call(client, contract, %{})
    end

    test "sends custom headers" do
      Req.Test.stub(__MODULE__, fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        assert auth_header == ["Bearer token123"]

        Req.Test.json(conn, [])
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          headers: %{"authorization" => "Bearer token123"},
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = list_users_contract()

      assert {:ok, []} = Client.call(client, contract, %{})
    end

    test "returns validation error for invalid input" do
      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = find_user_contract()

      result = Client.call(client, contract, %{id: "not_a_number"})

      assert {:error, %Client.ValidationError{phase: :input}} = result
    end

    test "returns validation error for missing required input" do
      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = create_user_contract()

      result = Client.call(client, contract, %{})

      assert {:error, %Client.ValidationError{phase: :input}} = result
    end

    test "returns validation error for invalid output" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"invalid" => "response"})
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = find_user_contract()

      result = Client.call(client, contract, %{id: 123})

      assert {:error, %Client.ValidationError{phase: :output}} = result
    end

    test "returns server error for non-2xx response" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          404,
          Jason.encode!(%{"code" => "NOT_FOUND", "message" => "User not found"})
        )
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}, retry: false]
        )

      contract = find_user_contract()

      result = Client.call(client, contract, %{id: 999})

      assert {:error,
              %Client.ServerError{status: 404, code: "NOT_FOUND", message: "User not found"}} =
               result
    end

    test "handles trailing slash in base_url" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/api/users"

        Req.Test.json(conn, [])
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api/",
          req_options: [plug: {Req.Test, __MODULE__}]
        )

      contract = list_users_contract()

      assert {:ok, []} = Client.call(client, contract, %{})
    end

    test "returns request error on transport failure" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}, retry: false]
        )

      contract = list_users_contract()

      result = Client.call(client, contract, %{})

      assert {:error, %Client.RequestError{reason: %Req.TransportError{reason: :timeout}}} =
               result
    end

    test "handles non-map error response body" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(500, "Internal Server Error")
      end)

      client =
        Client.new(
          base_url: "http://localhost:4000/api",
          req_options: [plug: {Req.Test, __MODULE__}, retry: false]
        )

      contract = list_users_contract()

      result = Client.call(client, contract, %{})

      assert {:error, %Client.ServerError{status: 500, code: nil}} = result
    end
  end

  describe "call!/3" do
    test "returns result on success" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, [])
      end)

      contract =
        Zoi.RPC.new()
        |> Zoi.RPC.route(method: :get, path: "/users")
        |> Zoi.RPC.output(Zoi.array(Zoi.object(%{}, coerce: true)))

      client =
        Client.new(base_url: "http://localhost:4000", req_options: [plug: {Req.Test, __MODULE__}])

      assert [] = Client.call!(client, contract, %{})
    end

    test "raises ValidationError on invalid input" do
      contract =
        Zoi.RPC.new()
        |> Zoi.RPC.route(method: :get, path: "/users/:id")
        |> Zoi.RPC.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
        |> Zoi.RPC.output(Zoi.object(%{}, coerce: true))

      client =
        Client.new(base_url: "http://localhost:4000", req_options: [plug: {Req.Test, __MODULE__}])

      assert_raise Client.ValidationError, fn ->
        Client.call!(client, contract, %{id: "invalid"})
      end
    end

    test "raises ServerError on server error" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          500,
          Jason.encode!(%{"code" => "ERROR", "message" => "Server error"})
        )
      end)

      contract =
        Zoi.RPC.new()
        |> Zoi.RPC.route(method: :get, path: "/users")
        |> Zoi.RPC.output(Zoi.array(Zoi.object(%{}, coerce: true)))

      client =
        Client.new(
          base_url: "http://localhost:4000",
          req_options: [plug: {Req.Test, __MODULE__}, retry: false]
        )

      assert_raise Client.ServerError, fn ->
        Client.call!(client, contract, %{})
      end
    end
  end

  describe "module-based client" do
    # Define a test client with req_options for testing
    defmodule TestClient do
      use Zoi.RPC.Client,
        base_url: "http://localhost:4000/api",
        headers: %{"x-test" => "true"},
        req_options: [plug: {Req.Test, Zoi.RPC.ClientTest}],
        contracts: Zoi.RPC.TestContract.contracts()
    end

    test "client/0 returns configured client" do
      client = TestClient.client()

      assert client.base_url == "http://localhost:4000/api"
      assert client.headers == %{"x-test" => "true"}
    end

    test "generated function calls endpoint" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/users"

        Req.Test.json(conn, [%{"id" => 1, "name" => "Alice"}])
      end)

      assert {:ok, [%{id: 1, name: "Alice"}]} = TestClient.list_users(%{page: 1})
    end

    test "generated function with path params" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/users/123"

        Req.Test.json(conn, %{"id" => 123, "name" => "Bob"})
      end)

      assert {:ok, %{id: 123, name: "Bob"}} = TestClient.find_user(%{id: 123})
    end

    test "generated function with body" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/users"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "Charlie"}

        Req.Test.json(conn, %{"id" => 1, "name" => "Charlie"})
      end)

      assert {:ok, %{id: 1, name: "Charlie"}} = TestClient.create_user(%{name: "Charlie"})
    end

    test "generated bang function raises on error" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          404,
          Jason.encode!(%{"code" => "NOT_FOUND", "message" => "Not found"})
        )
      end)

      assert_raise Client.ServerError, fn ->
        TestClient.find_user!(%{id: 999})
      end
    end

    test "generated bang function returns result on success" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"id" => 1, "name" => "Alice"})
      end)

      assert %{id: 1, name: "Alice"} = TestClient.find_user!(%{id: 1})
    end

    test "sends configured headers" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-test") == ["true"]

        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = TestClient.list_users()
    end

    test "uses default input when none provided" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.query_string == "page=1"

        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = TestClient.list_users()
    end
  end
end
