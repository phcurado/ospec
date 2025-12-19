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

      # In a shared package: my_api_contract
      defmodule MyAPI.Contract do
        @user Zoi.object(%{
          id: Zoi.integer(),
          name: Zoi.string(),
          email: Zoi.string()
        })

        def user_schema, do: @user

        def list_users do
          Zoi.RPC.new()
          |> Zoi.RPC.route(method: :get, path: "/users")
          |> Zoi.RPC.input(
            query: Zoi.object(%{
              page: Zoi.integer() |> Zoi.default(1),
              page_size: Zoi.integer() |> Zoi.default(20)
            })
          )
          |> Zoi.RPC.output(Zoi.array(@user))
        end

        def find_user do
          Zoi.RPC.new()
          |> Zoi.RPC.route(method: :get, path: "/users/:id")
          |> Zoi.RPC.input(
            params: Zoi.object(%{id: Zoi.integer()})
          )
          |> Zoi.RPC.output(@user)
        end

        def create_user do
          Zoi.RPC.new()
          |> Zoi.RPC.route(method: :post, path: "/users")
          |> Zoi.RPC.input(
            body: Zoi.object(%{
              name: Zoi.string(),
              email: Zoi.string()
            })
          )
          |> Zoi.RPC.output(@user)
        end
      end

  ### Input Sources

  The `input/2` function accepts separate schemas for different input sources:

  - `:params` - Path parameters (e.g., `/users/:id`)
  - `:query` - Query string parameters (e.g., `?page=1&page_size=20`)
  - `:body` - Request body (JSON payload)

  ## Server

  The server adds handlers to the contracts. Handlers are anonymous functions that
  receive the validated input and the `Plug.Conn`, allowing you to call your existing
  business logic.

      defmodule MyApp.API do
        def routes do
          %{
            users: %{
              list: MyAPI.Contract.list_users()
                    |> Zoi.RPC.handler(fn input, conn ->
                      users = MyApp.Users.list(input.page, input.page_size)
                      {:ok, users}
                    end),

              find: MyAPI.Contract.find_user()
                    |> Zoi.RPC.handler(fn input, conn ->
                      case MyApp.Users.get(input.id) do
                        nil -> {:error, :not_found}
                        user -> {:ok, user}
                      end
                    end),

              create: MyAPI.Contract.create_user()
                      |> Zoi.RPC.handler(fn input, conn ->
                        current_user = conn.assigns.current_user

                        case MyApp.Users.create(input, created_by: current_user) do
                          {:ok, user} -> {:ok, user}
                          {:error, changeset} -> {:error, changeset}
                        end
                      end)
            }
          }
        end
      end

  ### Plug Integration

  Add `Zoi.RPC.Plug` to your Phoenix router. It integrates with existing pipelines,
  so authentication and other middleware work as expected:

      # In your Phoenix router
      pipeline :api do
        plug :accepts, ["json"]
        plug MyApp.AuthPlug  # Sets conn.assigns.current_user
      end

      scope "/api" do
        pipe_through :api
        forward "/", Zoi.RPC.Plug, routes: &MyApp.API.routes/0
      end

  The handler receives `conn` with all assigns populated by previous plugs.

  ## Client

  The client uses the same contract for type-safe requests. It validates input before
  sending and validates output on response.

      # In your client application (depends on my_api_contract)
      defmodule MyApp.Client do
        use Zoi.RPC.Client,
          base_url: "http://localhost:4000",
          contract: MyAPI.Contract
      end

  Call API methods with validated inputs and outputs:

      {:ok, users} = MyApp.Client.users_list(%{page: 1, page_size: 10})
      {:ok, user} = MyApp.Client.users_find(%{id: 123})
      {:ok, new_user} = MyApp.Client.users_create(%{name: "Alice", email: "alice@example.com"})

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

  @output_schema Zoi.struct(Zoi.Types.Object)

  @handler_schema Zoi.function(arity: 2)

  @schema Zoi.struct(__MODULE__, %{
            route: @route_schema,
            input: @input_schema |> Zoi.optional(),
            output: @output_schema |> Zoi.optional(),
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
  """
  @spec output(t(), unquote(Zoi.type_spec(@output_schema))) :: t()
  def output(rpc, output) do
    Zoi.parse!(@output_schema, output)
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
