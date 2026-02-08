defmodule Ospec.ApiSpec do
  @moduledoc """
  Defines an API specification for OpenAPI generation.

      defmodule MyApp.ApiSpec do
        use Ospec.ApiSpec

        @impl true
        def spec do
          %{
            openapi: "3.1.0",
            info: %{title: "My API", version: "1.0.0"},
            paths: Ospec.OpenAPI.paths(:my_app),
            components: Ospec.OpenAPI.components([
              MyApp.Schemas.user(),
              MyApp.Schemas.error()
            ])
          }
        end
      end

  Schemas with `ref` metadata become components:

      def user do
        Zoi.map(%{id: Zoi.integer(), name: Zoi.string()}, metadata: [ref: :User])
      end
  """

  @callback spec() :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour Ospec.ApiSpec
    end
  end
end
