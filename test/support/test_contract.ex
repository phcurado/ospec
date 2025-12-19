defmodule Zoi.RPC.TestContract do
  @moduledoc false

  @user_schema Zoi.object(%{id: Zoi.integer(), name: Zoi.string()}, coerce: true)

  def contracts do
    %{
      list_users:
        Zoi.RPC.new()
        |> Zoi.RPC.route(method: :get, path: "/users")
        |> Zoi.RPC.input(
          query: Zoi.object(%{page: Zoi.integer() |> Zoi.default(1)}, coerce: true)
        )
        |> Zoi.RPC.output(Zoi.array(@user_schema)),
      find_user:
        Zoi.RPC.new()
        |> Zoi.RPC.route(method: :get, path: "/users/:id")
        |> Zoi.RPC.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
        |> Zoi.RPC.output(@user_schema),
      create_user:
        Zoi.RPC.new()
        |> Zoi.RPC.route(method: :post, path: "/users")
        |> Zoi.RPC.input(body: Zoi.object(%{name: Zoi.string()}, coerce: true))
        |> Zoi.RPC.output(@user_schema)
    }
  end
end
