defmodule Zoi.RPC do
  @moduledoc """
  End-to-end type-safe APIs for Elixir using `Zoi` schemas and OpenAPI standards.

  Zoi.RPC enables you to define API contracts with typed inputs and outputs, then share
  those contracts between server and client for guaranteed type safety on both ends.

  ## Features

  - Type-safe API definitions using `Zoi` schemas
  - Separate input sources: path params, query string, request body
  - Shared contracts between server and client
  - OpenAPI documentation generation via `Zoi.JSONSchema`
  - Integrates with Phoenix/Plug pipelines for middleware (auth, logging, etc.)

  ## Installation

  Add `zoi_rpc` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:zoi_rpc, "~> 0.1.0"}
        ]
      end

  ## Contract Definition

  Contracts define the API schema without implementation. They can be shared as a
  separate package between server and client applications.

  Define contracts in a `contracts/0` function that returns a map:

  **Important:** HTTP params have string keys. Use `coerce: true` on `Zoi.object` schemas
  to normalize string keys to atoms for matching.

      # In a shared package: my_api_contract
      defmodule MyAPI.Contract do
        # Output schemas don't need coerce since they use atom keys from Elixir data
        @user Zoi.object(%{
          id: Zoi.integer(),
          name: Zoi.string(),
          email: Zoi.string()
        })

        def contracts do
          %{
            list_users:
              Zoi.RPC.new()
              |> Zoi.RPC.route(method: :get, path: "/users")
              |> Zoi.RPC.input(
                query: Zoi.object(%{
                  page: Zoi.integer() |> Zoi.default(1),
                  page_size: Zoi.integer() |> Zoi.default(20)
                }, coerce: true)
              )
              |> Zoi.RPC.output(Zoi.array(@user)),

            find_user:
              Zoi.RPC.new()
              |> Zoi.RPC.route(method: :get, path: "/users/:id")
              |> Zoi.RPC.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
              |> Zoi.RPC.output(@user),

            create_user:
              Zoi.RPC.new()
              |> Zoi.RPC.route(method: :post, path: "/users")
              |> Zoi.RPC.input(
                body: Zoi.object(%{
                  name: Zoi.string(),
                  email: Zoi.string()
                }, coerce: true)
              )
              |> Zoi.RPC.output(@user)
          }
        end
      end

  ### Input Sources

  The `input/2` function accepts separate schemas for different input sources:

  - `:params` - Path parameters (e.g., `/users/:id`)
  - `:query` - Query string parameters (e.g., `?page=1&page_size=20`)
  - `:body` - Request body (JSON payload)

  ## Server

  Use `Zoi.RPC.Handler` in your Phoenix controllers. It validates input,
  calls your handler, validates output, and returns JSON responses.

      defmodule MyAppWeb.UsersController do
        use MyAppWeb, :controller
        import Zoi.RPC.Handler

        @contracts MyAPI.Contract.contracts()

        def list(conn, params) do
          handle(conn, params, @contracts.list_users, fn input, _conn ->
            users = MyApp.Users.list(input.page, input.page_size)
            {:ok, users}
          end)
        end

        def find(conn, params) do
          handle(conn, params, @contracts.find_user, fn input, _conn ->
            case MyApp.Users.get(input.id) do
              nil -> {:error, :not_found}
              user -> {:ok, user}
            end
          end)
        end

        def create(conn, params) do
          handle(conn, params, @contracts.create_user, fn input, conn ->
            current_user = conn.assigns.current_user

            case MyApp.Users.create(input, created_by: current_user) do
              {:ok, user} -> {:ok, user}
              {:error, changeset} -> {:error, changeset}
            end
          end)
        end
      end

  ### Phoenix Router

  Add routes in your Phoenix router pointing to the controller:

      # In your Phoenix router
      pipeline :api do
        plug :accepts, ["json"]
        plug MyApp.AuthPlug  # Sets conn.assigns.current_user
      end

      scope "/api", MyAppWeb do
        pipe_through :api

        get "/users", UsersController, :list
        get "/users/:id", UsersController, :find
        post "/users", UsersController, :create
      end

  This leverages Phoenix's battle-tested routing while Zoi.RPC handles validation.

  ## Client

  The client uses the same contract for type-safe requests. It validates input before
  sending and validates output on response. Requires `{:req, "~> 0.5"}` in your dependencies.

      defmodule MyApp.APIClient do
        use Zoi.RPC.Client,
          base_url: "http://localhost:4000/api",
          headers: %{"authorization" => "Bearer token"},
          contracts: MyAPI.Contract.contracts()
      end

      # Auto-generates functions from contracts:
      {:ok, users} = MyApp.APIClient.list_users(%{page: 1})
      {:ok, user} = MyApp.APIClient.find_user(%{id: 123})
      user = MyApp.APIClient.find_user!(%{id: 123})  # raises on error

  The client handles:
  - Input validation against the contract's input schema
  - URL building from route and path params
  - Query params and JSON body serialization
  - Output validation against the contract's output schema
  - Error responses with `ValidationError`, `RequestError`, or `ServerError`

  ## Architecture

  The recommended architecture separates concerns into three packages:

  1. **Contract package** (`my_api_contract`) - Schema definitions only, depends on `:zoi`
  2. **Server** - Depends on contract + Phoenix/Ecto/your stack, adds handlers
  3. **Client** - Depends on contract + HTTP client (e.g., Req)

  This ensures the client stays lightweight and doesn't pull in server dependencies,
  while both sides share the exact same type definitions.
  """

  @route_schema Zoi.keyword(method: Zoi.enum([:get, :post, :put, :delete]), path: Zoi.string())

  @input_schema Zoi.keyword(
                  params: Zoi.struct(Zoi.Types.Object) |> Zoi.optional(),
                  query: Zoi.struct(Zoi.Types.Object) |> Zoi.optional(),
                  body: Zoi.struct(Zoi.Types.Object) |> Zoi.optional()
                )

  @handler_schema Zoi.function(arity: 2)

  @schema Zoi.struct(__MODULE__, %{
            route: @route_schema,
            input: @input_schema |> Zoi.optional(),
            output: Zoi.any() |> Zoi.optional(),
            handler: @handler_schema |> Zoi.optional()
          })

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)

  defstruct Zoi.Struct.struct_fields(@schema)

  @spec new() :: t()
  def new() do
    %__MODULE__{
      route: %{method: :get, path: "/"},
      input: nil,
      output: nil,
      handler: nil
    }
  end

  @doc """
  Sets the HTTP route (method and path) for the endpoint.

  #{Zoi.describe(@route_schema)}
  """
  @spec route(t(), unquote(Zoi.type_spec(@route_schema))) :: t()
  def route(rpc, route) do
    Zoi.parse!(@route_schema, route)
    %{rpc | route: route}
  end

  @doc """
  Sets the input schemas for the endpoint.

  #{Zoi.describe(@input_schema)}
  """
  @spec input(t(), unquote(Zoi.type_spec(@input_schema))) :: t()
  def input(rpc, input) do
    Zoi.parse!(@input_schema, input)
    %{rpc | input: input}
  end

  @doc """
  Sets the output schema for the endpoint.

  Accepts any Zoi schema type (object, array, string, etc.).
  """
  @spec output(t(), Zoi.type()) :: t()
  def output(rpc, output) do
    %{rpc | output: output}
  end

  @doc """
  Sets the handler function for the endpoint.

  The handler receives the validated input and `Plug.Conn`, and should return
  `{:ok, result}` or `{:error, reason}`.
  """
  @spec handler(t(), unquote(Zoi.type_spec(@handler_schema))) :: t()
  def handler(rpc, handler) do
    Zoi.parse!(@handler_schema, handler)
    %{rpc | handler: handler}
  end
end
