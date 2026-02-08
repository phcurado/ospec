# Ospec

> **Warning:** This library is under active development and not yet published to Hex. The API may change.

End-to-end type-safe APIs for Elixir using `Zoi` schemas and OpenAPI standards.

## Installation

Add `ospec` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ospec, "~> 0.1.0"}
  ]
end
```

## Quick Start

Define specs directly in your controller:

```elixir
defmodule MyAppWeb.UsersController do
  use MyAppWeb, :controller
  use Ospec.Controller

  @user Zoi.map(%{id: Zoi.integer(), name: Zoi.string(), email: Zoi.string()},
    metadata: [ref: :User]
  )

  ospec :index,
    Ospec.new()
    |> Ospec.route(:get, "/api/users")
    |> Ospec.tags(["users"])
    |> Ospec.summary("List users")
    |> Ospec.input(query: Zoi.map(%{page: Zoi.integer() |> Zoi.default(1)}))
    |> Ospec.output(Zoi.array(@user))

  ospec :show,
    Ospec.new()
    |> Ospec.route(:get, "/api/users/:id")
    |> Ospec.tags(["users"])
    |> Ospec.summary("Get user")
    |> Ospec.input(params: Zoi.map(%{id: Zoi.integer()}))
    |> Ospec.output(@user)
    |> Ospec.responses(%{404 => Ospec.Schemas.error()})

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
```

## OpenAPI Generation

Create an ApiSpec module:

```elixir
defmodule MyAppWeb.ApiSpec do
  use Ospec.ApiSpec

  @impl true
  def spec do
    %{
      openapi: "3.0.3",
      info: %{title: "My API", version: "1.0.0"},
      paths: Ospec.OpenAPI.paths(:my_app),
      components: Ospec.OpenAPI.components(:my_app)  # auto-discovers schemas
    }
  end
end
```

Generate the OpenAPI spec:

```
mix ospec.openapi MyAppWeb.ApiSpec --output openapi.json
```

## Swagger UI

Add to your router:

```elixir
get "/api/openapi", Ospec.OpenAPI.Spec, api_spec: MyAppWeb.ApiSpec
forward "/docs", Ospec.OpenAPI.Swagger, path: "/api/openapi"
```

Visit `/docs` to see the Swagger UI.

## Input Validation

The `Ospec.Plug` automatically validates incoming requests:

- Path parameters via `params:`
- Query parameters via `query:`
- Request body via `body:`

Access validated input in your controller:

```elixir
def show(conn, _params) do
  input = Ospec.Conn.get_input(conn)
  # input.params, input.query, input.body are validated
end
```

## Output Validation

Use `Ospec.Conn.json/3` to validate responses:

```elixir
Ospec.Conn.json(conn, user)           # validates against output schema
Ospec.Conn.json(conn, user, 201)      # with status code
```

If validation fails, logs the error and returns 500.

## Schemas with `ref`

Add `metadata: [ref: :Name]` to schemas that should become OpenAPI components:

```elixir
@user Zoi.map(%{id: Zoi.integer(), name: Zoi.string()}, metadata: [ref: :User])
```

Schemas with `ref` are auto-discovered and become `$ref` in the OpenAPI spec.

## Built-in Schemas

Ospec provides common schemas:

```elixir
Ospec.Schemas.error()  # Standard error response with ref: :Error
```

## Reusable Schemas

For schemas shared across multiple controllers, extract to a module:

```elixir
defmodule MyApp.Schemas do
  def user do
    Zoi.map(%{id: Zoi.integer(), name: Zoi.string()}, metadata: [ref: :User])
  end

  def post do
    Zoi.map(%{id: Zoi.integer(), title: Zoi.string(), author: user()},
      metadata: [ref: :Post]
    )
  end
end
```

Then use in controllers:

```elixir
ospec :index,
  Ospec.new()
  |> Ospec.output(Zoi.array(MyApp.Schemas.user()))
```

## License

Copyright 2025 Paulo Curado

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
