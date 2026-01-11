# Ospec

> **Warning:** This library is under active development and not yet published to Hex. The API may change.

End-to-end type-safe APIs for Elixir using `Zoi` schemas and OpenAPI standards.

Ospec enables you to define API contracts with typed inputs and outputs, then share those contracts between applications with type safety on both ends.

## Why?

This library aims to address a common challenge when building Elixir applications that needs explicit contracts and API definitions.

Ospec helps you define your API contracts with typed inputs and outputs. These contracts serve as the source of truth for your API, enabling input/output validation and OpenAPI documentation generation. If you have multiple services communicating with each other, contracts can be shared as a separate package - but for most use cases, you'll just define them directly in your Phoenix application.

## Installation

Add `ospec` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ospec, "~> 0.1.0"}
  ]
end
```

Also add in the `formatter.exs` file to format the code properly:

```elixir
[
  import_deps: [:ospec]
]
```

## Contract Definition

Contracts define the API schema without implementation. For most applications, you'll define contracts directly in your Phoenix app. If you have microservices or separate Elixir applications that need to communicate, you can extract contracts into a shared package.

Let's imagine we have a simple User API with three endpoints:

```elixir
defmodule MyApp.APISpec do
  @behaviour Ospec

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
```

The `input/2` function accepts separate schemas for different input sources: `:params` for path parameters (`/users/:id`), `:query` for query string parameters (`?page=1`), and `:body` for request body (JSON payload).

You can architect your contract module the way it makes the most sense for your project. As you can see, the contract definitions are just plain functions that define the shape of your API.

## Server

Now with the contract defined, you can just reference the contract definitions in your controllers to implement the server logic.

```elixir
defmodule MyAppWeb.UsersController do
  use MyAppWeb, :controller

  alias MyApp.APISpec

  def list(conn, _params) do
    Ospec.handle(conn, APISpec.list_users(), fn input, _conn ->
      users = MyApp.Users.list(input.page, input.page_size)
      {:ok, users}
    end)
  end

  def find(conn, _params) do
    Ospec.handle(conn, APISpec.find_user(), fn input, _conn ->
      case MyApp.Users.get(input.id) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end)
  end

  def create(conn, _params) do
    Ospec.handle(conn, APISpec.create_user(), fn input, conn ->
      current_user = conn.assigns.current_user

      case MyApp.Users.create(input, created_by: current_user) do
        {:ok, user} -> {:ok, user}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end
end
```

`Ospec.handle/3` validates the input against the defined schema, calls the handler function, and validates the output before sending the response. Input is automatically extracted from the appropriate `conn` fields based on the contract's input schema (`:params` from `conn.path_params`, `:query` from `conn.query_params`, `:body` from `conn.body_params`).

### Phoenix Router

Finally, set up the routes in your Phoenix router:

```elixir
pipeline :api do
  plug :accepts, ["json"]
end

scope "/api", MyAppWeb do
  pipe_through :api

  get "/users", UsersController, :list
  get "/users/:id", UsersController, :find
  post "/users", UsersController, :create
end
```

Nothing different from a regular Phoenix setup!

You can also leverage `Ospec.Router` to automatically generate routes from the contract definitions:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use Ospec.Router, contracts: MyApp.APISpec.api_spec()

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MyAppWeb do
    pipe_through :api

    ospec :list_users, UsersController, :list
    ospec :find_user, UsersController, :find
    ospec :create_user, UsersController, :create
  end
end
```

The `ospec/3` macro will generate the method and path based on the contract definition.

## Client

The client is useful when you have separate applications communicating with each other. If you extracted your contracts into a shared package, the consumer application can use `Ospec.Client` with automatically generated type-safe functions. By default, `Ospec` uses `Req` as the HTTP client.

```elixir
defmodule Billing.UserAPIClient do
  use Ospec.Client,
    base_url: "http://localhost:4000/api",
    headers: %{"authorization" => "Bearer token"},
    contracts: MyApp.APISpec.api_spec()
end

# Auto-generates functions from contracts:
{:ok, users} = Billing.UserAPIClient.list_users(%{page: 1})
{:ok, user} = Billing.UserAPIClient.find_user(%{id: 123})
user = Billing.UserAPIClient.find_user!(%{id: 123})  # raises on error
```

Everything with the type safety and validation provided by `Zoi`:

```elixir
# Input validation
{:error, %ValidationError{}} = Billing.UserAPIClient.find_user(%{id: "not_an_integer"})

# Output validation
{:error, %ValidationError{}} = Billing.UserAPIClient.find_user(%{id: 9999}) # server returns invalid data
```

## OpenAPI Documentation

Since definitions are based on `Zoi` schemas, you can easily generate OpenAPI documentation from the contracts. `Zoi` can generate JSON Schema, which OpenAPI 3.1 supports natively. To enable it, add the [oaskit](https://hexdocs.pm/oaskit/Oaskit.html) package to your project:

```elixir
def deps do
  [
    {:ospec, "~> 0.1.0"},
    {:oaskit, "~> 0.9"}
  ]
end
```

Then, generate OpenAPI documentation from the contract definitions:

```elixir
defmodule MyAppWeb.APISpec do
  alias Oaskit.Spec.Paths
  alias Oaskit.Spec.Server

  alias MyApp.APISpec

  def spec() do
    %{
      openapi: "3.1.1",
      info: %{
        title: "My App API",
        version: "1.0.0",
        description: "Main HTTP API for My App"
      },
      servers: [Server.from_config(:my_app, MyAppWeb.Endpoint)],
      paths: Paths.from_router(MyAppWeb.Router, filter: &String.starts_with?(&1.path, "/api/")),
      components: %{
        schemas: Ospec.OpenAPI.schemas_from_contracts(APISpec.api_spec())
      }
    }
  end
end
```

Now you just reference on your controller which functions should be documented:

```elixir
defmodule MyAppWeb.UsersController do
  use MyAppWeb, :controller
  use Ospec.OpenAPI

  alias MyApp.APISpec

  open_api APISpec.list_users()
  def list(conn, _params) do
    Ospec.handle(conn, APISpec.list_users(), fn input, _conn ->
      users = MyApp.Users.list(input.page, input.page_size)
      {:ok, users}
    end)
  end

  open_api APISpec.find_user()
  def find(conn, _params) do
    Ospec.handle(conn, APISpec.find_user(), fn input, _conn ->
      case MyApp.Users.get(input.id) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end)
  end

  open_api APISpec.create_user()
  def create(conn, _params) do
    Ospec.handle(conn, APISpec.create_user(), fn input, conn ->
      current_user = conn.assigns.current_user

      case MyApp.Users.create(input, created_by: current_user) do
        {:ok, user} -> {:ok, user}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end
end
```

This will automatically include the endpoint in the OpenAPI documentation, based on the contract definition.

## Roadmap

- `Ospec.Contract` behaviour
- `Ospec.Router` with `ospec/3` macro for route generation
- `Ospec.OpenAPI` integration with oaskit
- TypeScript type and client generation from contracts

## License

Copyright 2025 Paulo Curado

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
