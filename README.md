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

## Usage

Ospec separates API definition into two parts: **contracts** (input/output schemas) and **routing** (method/path). This separation helps to shape and define the API, which will be later used to generate routes and OpenAPI docs.

### Defining Routes

Routes define method and path using `scope` and `route`:

```elixir
defmodule MyApp.APISpec do
  import Ospec.API

  def api_spec do
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
```

### Defining Contracts

Contracts define input, output, and controller:

```elixir
defmodule MyApp.APISpec do

  # ...contracts

  @user Zoi.map(%{
    id: Zoi.integer(),
    name: Zoi.string(),
    email: Zoi.string()
  })

  def list_users do
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

  def find_user do
    Ospec.new()
    |> Ospec.input(params: Zoi.map(%{id: Zoi.integer()}))
    |> Ospec.output(@user)
    |> Ospec.controller(MyAppWeb.UsersController, :show)
  end

  def create_user do
    Ospec.new()
    |> Ospec.input(body: Zoi.map(%{name: Zoi.string(), email: Zoi.string()}))
    |> Ospec.output(@user)
    |> Ospec.controller(MyAppWeb.UsersController, :create)
  end
end
```

### Phoenix Integration

Generate Phoenix routes from your API specification:

```elixir
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
```

### Controllers

Controllers receive validated input via `Ospec.Conn.get_input/1`:

```elixir
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

  def create(conn, _params) do
    input = Ospec.Conn.get_input(conn)
    case MyApp.Accounts.create_user(input.body) do
      {:ok, user} -> Ospec.HTTP.created(user)
      {:error, changeset} -> Ospec.HTTP.bad_request(changeset)
    end
  end
end
```

Response helpers available in `Ospec.HTTP`:

```elixir
Ospec.HTTP.ok(data)           # 200 OK
Ospec.HTTP.created(data)      # 201 Created
Ospec.HTTP.no_content()       # 204 No Content
Ospec.HTTP.bad_request(data)  # 400 Bad Request
Ospec.HTTP.unauthorized()     # 401 Unauthorized
Ospec.HTTP.forbidden()        # 403 Forbidden
Ospec.HTTP.not_found()        # 404 Not Found
```

### Middleware

Add middleware to scopes:

```elixir
def api_spec do
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
```

Middleware receives `conn` and `next`:

```elixir
def authenticate(conn, next) do
  case get_user_from_token(conn) do
    {:ok, user} ->
      conn = assign(conn, :current_user, user)
      next.(conn)
    :error ->
      conn |> send_resp(401, "Unauthorized") |> halt()
  end
end
```

## OpenAPI Generation

Generate an OpenAPI specification from your API:

```
mix ospec.openapi --output openapi.json
```

## License

Copyright 2025 Paulo Curado

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
