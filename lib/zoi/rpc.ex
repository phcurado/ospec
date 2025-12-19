defmodule Zoi.RPC do
  @moduledoc """
  Zoi.RPC aims to provide end to end type safety for your API. It leverages `Zoi` library to create typed schemas for your server and client, following OpenAPI standards.

  This library is a combination of `Zoi`, RPC (Remote Procedure Call) and OpenAPI. It allows you to define your API schema using `Zoi` types and automatically generates server and client code with OpenAPI documentation.

  ## Features

  - Type-safe API definitions using `Zoi` schemas.
  - Automatic generation of server and client code.
  - Built-in OpenAPI documentation generation.

  ## Installation

  Add `zoi_rpc` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:zoi_rpc, "~> 0.1.0"}
        ]
      end

    Then, run `mix deps.get` to fetch the dependencies.

  ## API Schema

  Define your API schema using `Zoi` types and use `Zoi.RPC` to generate server and client code.

      defmodule MyApp.Schemas do
        import Zoi.RPC

        @user_schema Zoi.object(%{
          id: Zoi.integer(),
          name: Zoi.string(),
          email: Zoi.string()
        })

        def list_users() do
          new()
          |> route(method: :get, path: "/users")
          |> input(Zoi.object(%{
            page: Zoi.integer(),
            page_size: Zoi.integer()
          }))
          |> output(Zoi.array(@user_schema))
          |> handler(fn input, context ->
            # Your logic to list users
            users = [
              %{id: 1, name: "Alice", email: "alice@example.com"},
              %{id: 2, name: "Bob", email: "bob@example.com"}
            ]

            {:ok, users}
          end)
        end

        def find_user() do
          new()
          |> route(method: :get, path: "/users/{id}")
          |> input(Zoi.object(%{
            id: Zoi.integer()
          }))
          |> output(@user_schema)
          |> handler(fn input, context ->
            # Your logic to find a user by ID
            user = %{id: 1, name: "Alice", email: "alice@example.com"}
            {:ok, user}
          end)
        end

        def create_user() do
          new()
          |> route(method: :post, path: "/users")
          |> input(Zoi.object(%{
            name: Zoi.string(),
            email: Zoi.string()
          }))
          |> output(@user_schema)
          |> handler(fn input, context ->
            # Your logic to create a new user
            new_user = %{id: 3, name: input.name, email: input.email}
            {:ok, new_user}
          end)
        end
      end

  ## Server

  Use `Zoi.RPC.Server` to create a server that serves your API.

      defmodule MyApp.Server do
        @behaviour Zoi.RPC.Server

        @impl true
        def spec(_) do
          %{
            users: %{
              find: MyApp.Schemas.find_user(),
              list: MyApp.Schemas.list_users(),
              create: MyApp.Schemas.create_user()
            }
          }
        end
      end

    Add the server into your Phoenix or Plug application:

      plug Zoi.RPC.Plug, server: MyApp.Server

  ## Client

  Use `Zoi.RPC.Client` to create a client that interacts with your API.

      defmodule MyOtherApp.MyAppClient do
        use Zoi.RPC.Client, base_url: "http://localhost:4000", spec: MyApp.Server
      end

    Now you can call your API methods with type safety:

      {:ok, users} = MyApp.Client.users.list(%{page: 1, page_size: 10})
      {:ok, user} = MyApp.Client.users.find(%{id: 1})
      {:ok, new_user} = MyApp.Client.users.create(%{name: "Charlie", email: "charlie@example.com"})
  """

  @route_schema Zoi.keyword(method: Zoi.enum([:get, :post, :put, :delete]), path: Zoi.string())
  @schema Zoi.struct(__MODULE__, %{
            route: @route_schema,
            input: Zoi.any(),
            output: Zoi.any(),
            handler: Zoi.any()
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
  Sets the route for the RPC.

  #{Zoi.describe(@route_schema)}
  """
  @spec route(t(), keyword()) :: t()
  def route(rpc, route) do
    Zoi.parse!(@route_schema, route)
    %{rpc | route: route}
  end
end
