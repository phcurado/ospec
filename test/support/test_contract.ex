defmodule Ospec.TestContract do
  @moduledoc false

  @user_schema Zoi.object(%{id: Zoi.integer(), name: Zoi.string()}, coerce: true)

  def contracts do
    %{
      list_users:
        Ospec.new()
        |> Ospec.route(method: :get, path: "/users")
        |> Ospec.input(
          query: Zoi.object(%{page: Zoi.integer() |> Zoi.default(1)}, coerce: true)
        )
        |> Ospec.output(Zoi.array(@user_schema)),
      find_user:
        Ospec.new()
        |> Ospec.route(method: :get, path: "/users/:id")
        |> Ospec.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
        |> Ospec.output(@user_schema),
      create_user:
        Ospec.new()
        |> Ospec.route(method: :post, path: "/users")
        |> Ospec.input(body: Zoi.object(%{name: Zoi.string()}, coerce: true))
        |> Ospec.output(@user_schema)
    }
  end
end
