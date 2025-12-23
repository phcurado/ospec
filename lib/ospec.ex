defmodule Ospec do
  @moduledoc """
  End-to-end type-safe APIs for Elixir using `Zoi` schemas and OpenAPI standards.

  Ospec enables you to define API contracts with typed inputs and outputs, then share
  those contracts between applications with type safety on both ends.

  ## Why?

  This library aims to address a common challenge when building Elixir applications that needs explicit contracts and API definitions.

  Imagine you have a Phoenix backend serving JSON APIs, being integrated with another Elixir app or a frontend app. Whenever you make a change
  to the API (adding fields, changing types, etc.), you need to ensure both sides stay in sync. This is where a shared contract definition becomes is
  useful, since it allows both sides to validate against the same schema. This library aims to facilitate creating shared contracts and explicit API definitions, leveraging `Zoi` for type safety, validation and JSON Schema for OpenAPI documentation.

  ## Installation

  Add `ospec` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:ospec, "~> 0.1.0"}
        ]
      end

  Also add in the `formatter.exs`  file to format the code properly:

      [
        import_deps: [:ospec]
      ]

  ## Contract Definition

  Contracts define the API schema without implementation. They can be shared as a separate package between server and client applications.

  It's recommended to create a dedicated package (ex: `my_api_contract`), and add your API definitions there. Think of this package as the "source of truth" for your API schema, which can act as a server contract and a client libray.


  Let's imagine we have a simple User API with three endpoints:

      # In your package: user_api
      defmodule UserAPI do
        @behaviour Ospec.Contract

        @user Zoi.object(%{
          id: Zoi.integer(),
          name: Zoi.string(),
          email: Zoi.string()
        })
   
        @impl true
        def api_spec() do
          %{
            find_user: find_user(),
            create_user: create_user(),
            list_users: list_users()
          }
        end

        def list_users() do
          Ospec.new()
          |> Ospec.route(method: :get, path: "/users")
          |> Ospec.input(
            query: Zoi.object(%{
              page: Zoi.integer() |> Zoi.default(1),
              page_size: Zoi.integer() |> Zoi.default(20)
            }, coerce: true)
          )
          |> Ospec.output(Zoi.array(@user))
        end

        def find_user() do
          Ospec.new()
          |> Ospec.route(method: :get, path: "/users/:id")
          |> Ospec.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
          |> Ospec.output(@user)
        end

        def create_user() do
          Ospec.new()
          |> Ospec.route(method: :post, path: "/users")
          |> Ospec.input(
            body: Zoi.object(%{
              name: Zoi.string(),
              email: Zoi.string()
            }, coerce: true)
          )
          |> Ospec.output(@user)
        end
      end

  The `input/2` function accepts separate schemas for different input sources:

  - `:params` - Path parameters (e.g., `/users/:id`)
  - `:query` - Query string parameters (e.g., `?page=1&page_size=20`)
  - `:body` - Request body (JSON payload)

  You can architect your contract module the way it makes the most sense for your project. As you can see, the contract definitions are just plain functions that defines the shape of your API.

  ## Server

  Now with the contract defined, you can just reference the contract definitions in your controllers to implement the server logic.

      defmodule UserAppWeb.UsersController do
        use UserAppWeb, :controller

        def list(conn, params) do
          Ospec.handle(conn, params, UserAPI.list_users(), fn input, _conn ->
            users = UserApp.Users.list(input.page, input.page_size)
            {:ok, users}
          end)
        end

        def find(conn, params) do
          Ospec.handle(conn, params, UserAPI.find_user(), fn input, _conn ->
            case UserApp.Users.get(input.id) do
              nil -> {:error, :not_found}
              user -> {:ok, user}
            end
          end)
        end

        def create(conn, params) do
          Ospec.handle(conn, params, UserAPI.create_user(), fn input, conn ->
            current_user = conn.assigns.current_user

            case UserApp.Users.create(input, created_by: current_user) do
              {:ok, user} -> {:ok, user}
              {:error, changeset} -> {:error, changeset}
            end
          end)
        end
      end

  `Ospec.handle/4` will validate the input against the defined schema, call the handler function, and validate the output before sending the response.

  ### Phoenix Router

  Finally, set up the routes in your Phoenix router:


      # In your Phoenix router
      pipeline :api do
        plug :accepts, ["json"]
      end

      scope "/api", MyAppWeb do
        pipe_through :api

        get "/users", UsersController, :list
        get "/users/:id", UsersController, :find
        post "/users", UsersController, :create
      end

  Nothing different from a regular Phoenix setup!

  You can also leverage `Ospec.Router` to automatically generate routes from the contract definitions.

      defmodule UserAppWeb.Router do
        use UserAppWeb, :router
        use Ospec.Router, contracts: UserAPI.api_spec(),

        pipeline :api do
          plug :accepts, ["json"]
        end

        scope "/api", MyAppWeb do
          pipe_through :api

          ospec :list_users, UserController, :list
          ospec :find_user, UserController, :find
          ospec :create_user, UserController, :create
        end
      end

  the `ospec/3` macro will generate the method and path based on the contract definition.

  ## Client

  Now that the server is set up, the consumer application can use the same contract defined by the shared package, with automatically generated type-safe functions for client requests. By default, `Ospec` uses `Req` as the HTTP client.
  Following the previous example, let's create a client for the User API, in our `Billing` application:

      defmodule Billing.UserAPIClient do
        use Ospec.Client,
          base_url: "http://localhost:4000/api",
          headers: %{"authorization" => "Bearer token"},
          contracts: UserAPI.api_spec()
      end

      # Auto-generates functions from contracts:
      {:ok, users} = Billing.UserAPIClient.list_users(%{page: 1})
      {:ok, user} = Billing.UserAPIClient.find_user(%{id: 123})
      user = Billing.UserAPIClient.find_user!(%{id: 123})  # raises on error

  Everything with the type safety and validation provided by `Zoi`:

      # Input validation
      {:error, %ValidationError{}} = Billing.UserAPIClient.find_user(%{id: "not_an_integer"})

      # Output validation
      {:error, %ValidationError{}} = Billing.UserAPIClient.find_user(%{id: 9999}) # server returns invalid data


  ## OpenAPI Documentation

  Since definitions are based on `Zoi` schemas, you can easily generate OpenAPI documentation from the contracts. `Zoi` can generate JSON Schema, which OpenAPI 3.1 supports natively. To enable it, add the [oaskit](https://hexdocs.pm/oaskit/Oaskit.html) package to your project:

      def deps do
        [
          {:ospec, "~> 0.1.0"},
          {:oaskit, "~> 0.9"}
        ]
      end

  Then, generate OpenAPI documentation from the contract definitions:

      defmodule UserAppWeb.APISpec do
        alias Oaskit.Spec.Paths
        alias Oaskit.Spec.Server

        def spec() do
          %{
            openapi: "3.1.1",
            info: %{
              title: "My App API",
              version: "1.0.0",
              description: "Main HTTP API for My App"
            },
            servers: [Server.from_config(:user_app, UserAppWeb.Endpoint)],
            paths: Paths.from_router(UserAppWeb.Router, filter: &String.starts_with?(&1.path, "/api/")),
            components: %{
              schemas: Ospec.OpenAPI.schemas_from_contracts(UserAPI.api_spec())
            }
          }
        end
      end

  Now you just reference on your controller, which functions should be documented:

      defmodule UserAppWeb.UsersController do
        use UserAppWeb, :controller

        import Ospec.OpenAPI

        open_api true
        def list(conn, params) do
          Ospec.handle(conn, params, UserAPI.list_users(), fn input, _conn ->
            users = UserApp.Users.list(input.page, input.page_size)
            {:ok, users}
          end)
        end

        open_api true
        def find(conn, params) do
          Ospec.handle(conn, params, UserAPI.find_user(), fn input, _conn ->
            case UserApp.Users.get(input.id) do
              nil -> {:error, :not_found}
              user -> {:ok, user}
            end
          end)
        end

        open_api true
        def create(conn, params) do
          Ospec.handle(conn, params, UserAPI.create_user(), fn input, conn ->
            current_user = conn.assigns.current_user

            case UserApp.Users.create(input, created_by: current_user) do
              {:ok, user} -> {:ok, user}
              {:error, changeset} -> {:error, changeset}
            end
          end)
        end
      end

  This will automatically include the endpoint in the OpenAPI documentation, based on the contract definition.
  """

  @route_schema Zoi.keyword(method: Zoi.enum([:get, :post, :put, :delete]), path: Zoi.string())

  @input_schema Zoi.keyword(
                  params: Zoi.struct(Zoi.Types.Map) |> Zoi.optional(),
                  query: Zoi.struct(Zoi.Types.Map) |> Zoi.optional(),
                  body: Zoi.struct(Zoi.Types.Map) |> Zoi.optional()
                )

  @handler_schema Zoi.function(arity: 2)

  @schema Zoi.struct(__MODULE__, %{
            route: @route_schema,
            input: @input_schema |> Zoi.optional(),
            output: Zoi.json() |> Zoi.optional(),
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
