defmodule Ospec do
  @moduledoc """
  End-to-end type-safe APIs for Elixir using `Zoi` schemas and OpenAPI standards.

  ## Installation

  Add `ospec` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:ospec, "~> 0.1.0"}
        ]
      end

  ## Usage

  Define specs directly in your controllers using `use Ospec.Controller`:

      defmodule MyAppWeb.UsersController do
        use MyAppWeb, :controller
        use Ospec.Controller

        @user Zoi.map(%{id: Zoi.integer(), name: Zoi.string()})

        ospec :index,
          Ospec.new()
          |> Ospec.route(:get, "/api/users")
          |> Ospec.input(query: Zoi.map(%{page: Zoi.integer() |> Zoi.default(1)}))
          |> Ospec.output(Zoi.array(@user))

        ospec :show,
          Ospec.new()
          |> Ospec.route(:get, "/api/users/:id")
          |> Ospec.input(params: Zoi.map(%{id: Zoi.integer()}))
          |> Ospec.output(@user)

        def index(conn, _params) do
          input = Ospec.Conn.get_input(conn)
          users = MyApp.Accounts.list_users(input.query)
          Ospec.Conn.json(conn, users)
        end

        def show(conn, _params) do
          input = Ospec.Conn.get_input(conn)
          case MyApp.Accounts.get_user(input.params.id) do
            nil -> conn |> put_status(404) |> json(%{error: "not found"})
            user -> Ospec.Conn.json(conn, user)
          end
        end
      end

  Specs can also be defined in a separate module and referenced:

      ospec :index, MyApp.ApiSpec.list_users()

  ## OpenAPI Generation

  Generate an OpenAPI specification from your controllers:

      mix ospec.openapi --output openapi.json
  """

  @route_schema Zoi.tuple({
                  Zoi.enum([:get, :post, :put, :patch, :delete]),
                  Zoi.string()
                })

  @input_schema Zoi.keyword(
                  params: Zoi.struct(Zoi.Types.Map) |> Zoi.optional(),
                  query: Zoi.struct(Zoi.Types.Map) |> Zoi.optional(),
                  body: Zoi.struct(Zoi.Types.Map) |> Zoi.optional()
                )

  @output_schema Zoi.json()

  @schema Zoi.struct(__MODULE__, %{
            route: @route_schema |> Zoi.nullish(),
            input: @input_schema |> Zoi.nullish(),
            output: @output_schema |> Zoi.nullish(),
            responses: Zoi.map(Zoi.integer(), Zoi.json()) |> Zoi.nullish(),
            tags: Zoi.array(Zoi.string()) |> Zoi.nullish(),
            summary: Zoi.string() |> Zoi.nullish(),
            description: Zoi.string() |> Zoi.nullish()
          })

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)

  defstruct Zoi.Struct.struct_fields(@schema)

  @spec new() :: t()
  def new do
    %__MODULE__{
      route: nil,
      input: nil,
      output: nil,
      responses: nil,
      tags: nil,
      summary: nil,
      description: nil
    }
  end

  @doc """
  Sets the HTTP method and path for the endpoint.

      Ospec.new()
      |> Ospec.route(:get, "/api/users")
      |> Ospec.route(:get, "/api/users/:id")
  """
  @spec route(t(), atom(), String.t()) :: t()
  def route(ospec, method, path) do
    Zoi.parse!(@route_schema, {method, path})
    %{ospec | route: {method, path}}
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
  Sets the output schema for the endpoint (200 response).

  Accepts any Zoi schema type (map, array, string, etc.).
  """
  @spec output(t(), unquote(Zoi.type_spec(@output_schema))) :: t()
  def output(ospec, output) do
    %{ospec | output: output}
  end

  @doc """
  Sets response schemas for specific status codes.

      Ospec.new()
      |> Ospec.responses(%{
        201 => @user,
        400 => @error,
        404 => @error
      })
  """
  @spec responses(t(), map()) :: t()
  def responses(ospec, responses) do
    %{ospec | responses: responses}
  end

  @doc """
  Sets tags for grouping operations in documentation.

      Ospec.new()
      |> Ospec.tags(["users"])
  """
  @spec tags(t(), [String.t()]) :: t()
  def tags(ospec, tags) do
    %{ospec | tags: tags}
  end

  @doc """
  Sets a short summary for the operation.

      Ospec.new()
      |> Ospec.summary("List all users")
  """
  @spec summary(t(), String.t()) :: t()
  def summary(ospec, summary) do
    %{ospec | summary: summary}
  end

  @doc """
  Sets a detailed description for the operation.

      Ospec.new()
      |> Ospec.description("Returns a paginated list of users.")
  """
  @spec description(t(), String.t()) :: t()
  def description(ospec, description) do
    %{ospec | description: description}
  end
end
