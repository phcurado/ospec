defmodule Ospec do
  @moduledoc """
  End-to-end type-safe APIs for Elixir using `Zoi` schemas and OpenAPI standards.

  Ospec enables you to define API contracts with typed inputs and outputs, then share
  those contracts between applications with type safety on both ends.

  ## Why?

  This library aims to address a common challenge when building Elixir applications that need explicit contracts and API definitions.

  Ospec helps you define your API contracts with typed inputs and outputs. These contracts serve as the source of truth for your API, enabling input/output validation and OpenAPI documentation generation. If you have multiple services communicating with each other, contracts can be shared as a separate package, but for most use cases, you'll just define them directly in your Phoenix or Plug-based application.

  ## Installation

  Add `ospec` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:ospec, "~> 0.1.0"}
        ]
      end

  ## API Definition

  `Ospec` supports API definition in a consistent and extensible way. Let's imagine we have a simple User API with three endpoints:

      defmodule MyApp.APISpec do
        import Ospec.API

        @user Zoi.map(%{
          id: Zoi.integer(),
          name: Zoi.string(),
          email: Zoi.string()
        })

        # Contracts define input, output, and controller
        def list_users() do
          Ospec.new()
          |> Ospec.input(
            query: Zoi.map(%{
              page: Zoi.integer() |> Zoi.default(1),
              page_size: Zoi.integer() |> Zoi.default(20)
            })
          )
          |> Ospec.output(Zoi.array(@user))
          |> Ospec.controller(MyAppWeb.UsersController, :index)
        end

        def find_user() do
          Ospec.new()
          |> Ospec.input(params: Zoi.map(%{id: Zoi.integer()}))
          |> Ospec.output(@user)
          |> Ospec.controller(MyAppWeb.UsersController, :show)
        end

        def create_user() do
          Ospec.new()
          |> Ospec.input(
            body: Zoi.map(%{
              name: Zoi.string(),
              email: Zoi.string()
            })
          )
          |> Ospec.output(@user)
          |> Ospec.controller(MyAppWeb.UsersController, :create)
        end

        # Routing defines method and path
        def api_spec() do
          new()
          |> scope("/api", fn router ->
            router
            |> scope("/users", fn router ->
              router
              |> route(:get, "/", list_users())
              |> route(:get, "/:id", find_user())
              |> route(:post, "/", create_user())
            end)
          end)
        end
      end

  You can architect your API spec module the way it makes the most sense for your project. As you can see, the definition is just plain functions that define the shape of your API.
  You can separate your API specification by domains or entities, like you would normally do with Phoenix Controllers, up to your application needs. For small applications it's recommended to add everything in a single module.

  ### Controller

  Controllers receive validated input via `Ospec.Conn.get_input/1`:

      defmodule MyAppWeb.UsersController do
        use MyAppWeb, :controller

        def index(conn, _params) do
          input = Ospec.Conn.get_input(conn)
          users = MyApp.Accounts.list_users(input.query)
          Ospec.HTTP.ok(users)
        end

        def show(conn, _params) do
          input = Ospec.Conn.get_input(conn)
          case MyApp.Accounts.get_user(input.params.id) do
            nil -> Ospec.HTTP.not_found()
            user -> Ospec.HTTP.ok(user)
          end
        end
      end

  Response helpers available in `Ospec.HTTP`:

      Ospec.HTTP.ok(data)           # 200 OK
      Ospec.HTTP.created(data)      # 201 Created
      Ospec.HTTP.no_content()       # 204 No Content
      Ospec.HTTP.bad_request(data)  # 400 Bad Request
      Ospec.HTTP.unauthorized()     # 401 Unauthorized
      Ospec.HTTP.forbidden()        # 403 Forbidden
      Ospec.HTTP.not_found()        # 404 Not Found

  The data passed to success responses is validated against the output schema before sending.

  ## Integrating with Phoenix

  Generate Phoenix routes from your API specification:

      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        import Ospec.Phoenix

        pipeline :api do
          plug :accepts, ["json"]
        end

        scope "/api" do
          pipe_through :api
          ospec_routes(MyApp.APISpec.api_spec(), prefix: "/api")
        end
      end

  Invalid requests receive a 422 response before reaching your controller.

  ### Middleware

  Add middleware to scopes using `middleware/2`:

      def api_spec() do
        new()
        |> scope("/api", fn router ->
          router
          |> middleware(&MyApp.Middleware.authenticate/2)
          |> scope("/users", fn router ->
            router
            |> route(:get, "/", list_users())
            |> route(:post, "/", create_user())
          end)
        end)
      end

  Middleware receives `conn` and `next`, calls `next.(conn)` to continue:

      def authenticate(conn, next) do
        case get_user_from_token(conn) do
          {:ok, user} ->
            conn = assign(conn, :current_user, user)
            next.(conn)
          :error ->
            conn |> send_resp(401, "Unauthorized") |> halt()
        end
      end

  ## OpenAPI Generation

  Generate an OpenAPI specification from your API:

      mix ospec.openapi --output openapi.json

  Since contracts define input and output schemas, the OpenAPI spec is generated automatically.
  """

  @input_schema Zoi.keyword(
                  params: Zoi.struct(Zoi.Types.Map) |> Zoi.optional(),
                  query: Zoi.struct(Zoi.Types.Map) |> Zoi.optional(),
                  body: Zoi.struct(Zoi.Types.Map) |> Zoi.optional()
                )

  @output_schema Zoi.json()

  @handler_schema Zoi.function(arity: 2)

  @controller_schema Zoi.tuple([Zoi.atom(), Zoi.atom()])

  @schema Zoi.struct(__MODULE__, %{
            input: @input_schema |> Zoi.nullish(),
            output: @output_schema |> Zoi.nullish(),
            handler: @handler_schema |> Zoi.nullish(),
            controller: @controller_schema |> Zoi.nullish()
          })

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)

  defstruct Zoi.Struct.struct_fields(@schema)

  @spec new() :: t()
  def new() do
    %__MODULE__{
      input: nil,
      output: nil,
      handler: nil,
      controller: nil
    }
  end

  @doc """
  Sets the input schemas for the endpoint.

  #{Zoi.describe(@input_schema)}
  """
  @spec input(t(), unquote(Zoi.type_spec(@input_schema))) :: t()
  def input(ospec, input) do
    Zoi.parse!(@input_schema, input)
    %{ospec | input: input}
  end

  @doc """
  Sets the output schema for the endpoint.

  Accepts any Zoi schema type (map, array, string, etc.).
  """

  @spec output(t(), unquote(Zoi.type_spec(@output_schema))) :: t()
  def output(ospec, output) do
    %{ospec | output: output}
  end

  @doc """
  Sets the controller module and action for the endpoint.

      |> Ospec.controller(MyAppWeb.UsersController, :index)
  """
  @spec controller(t(), module(), atom()) :: t()
  def controller(ospec, module, action) do
    %{ospec | controller: {module, action}}
  end

  @doc """
  Sets an inline handler function for the endpoint.

  Alternative to `controller/3` for simple cases. The handler receives
  `ctx` and `input`, returns a response using `Ospec.HTTP` helpers.

      |> Ospec.handler(fn ctx, input ->
        users = MyApp.Accounts.list_users(input.query)
        Ospec.HTTP.ok(users)
      end)
  """
  @spec handler(t(), unquote(Zoi.type_spec(@handler_schema))) :: t()
  def handler(ospec, handler) do
    Zoi.parse!(@handler_schema, handler)
    %{ospec | handler: handler}
  end
end
