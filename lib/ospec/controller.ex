defmodule Ospec.Controller do
  @moduledoc """
  Integrates Ospec with Phoenix controllers.

  Add `use Ospec.Controller` to your controller and define specs with the `ospec` macro:

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

  Specs can also reference a shared package:

      ospec :index, MyAPI.Spec.list_users()

  ## OpenAPI Generation

  Run `mix ospec.openapi` to generate OpenAPI specs from all controllers.
  """

  defmacro __using__(_opts) do
    quote do
      import Ospec.Controller, only: [ospec: 2]
      Module.register_attribute(__MODULE__, :ospec_specs, accumulate: true)
      @before_compile Ospec.Controller

      plug(Ospec.Plug)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __ospec_specs__ do
        Map.new(@ospec_specs)
      end
    end
  end

  @doc """
  Defines an Ospec spec for a controller action.

  The spec is used for:
  - Input validation (before action)
  - Output validation (via `Ospec.json/2`)
  - OpenAPI generation

  ## Examples

      # Inline spec
      ospec :index,
        Ospec.new()
        |> Ospec.route(:get, "/api/users")
        |> Ospec.input(query: Zoi.map(%{page: Zoi.integer()}))
        |> Ospec.output(Zoi.array(@user))

      # Reference to shared package
      ospec :index, MyAPI.Spec.list_users()
  """
  defmacro ospec(action, spec) do
    quote do
      @ospec_specs {unquote(action), unquote(spec)}
    end
  end
end
