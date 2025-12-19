defmodule Zoi.RPC.Handler do
  @moduledoc """
  Handles Zoi.RPC requests with input validation, handler execution, and output validation.

  ## Usage

  Import in your Phoenix controllers and use the `handle/4` function:

      defmodule MyAppWeb.UsersController do
        use MyAppWeb, :controller
        import Zoi.RPC.Handler

        @contracts MyAPI.Contract.contracts()

        def list(conn, params) do
          handle(conn, params, @contracts.list_users, fn input, _conn ->
            {:ok, MyApp.Repo.all(User)}
          end)
        end

        def find(conn, params) do
          handle(conn, params, @contracts.find_user, fn input, _conn ->
            case MyApp.Repo.get(User, input.id) do
              nil -> {:error, :not_found}
              user -> {:ok, user}
            end
          end)
        end
      end

  Then add routes in your Phoenix router:

      scope "/api", MyAppWeb do
        pipe_through :api

        get "/users", UsersController, :list
        get "/users/:id", UsersController, :find
      end
  """

  import Plug.Conn

  @doc """
  Handles an RPC request.

  1. Parses and validates input from params (path + query + body)
  2. Calls the handler function with validated input
  3. Validates output against the contract schema
  4. Returns JSON response

  ## Parameters

  - `conn` - The Plug.Conn
  - `params` - Phoenix params (merged path params, query params, body)
  - `contract` - The Zoi.RPC contract (without handler)
  - `handler` - Function `(input, conn) -> {:ok, result} | {:error, reason}`
  """
  def handle(conn, params, contract, handler) do
    with {:ok, input} <- validate_input(contract, params),
         {:ok, result} <- call_handler(handler, input, conn),
         {:ok, output} <- validate_output(contract, result) do
      send_json(conn, 200, output)
    else
      {:error, :validation, errors} ->
        tree = Zoi.treefy_errors(errors)
        send_error(conn, 422, "VALIDATION_ERROR", "Validation failed", tree)

      {:error, :not_found} ->
        send_error(conn, 404, "NOT_FOUND", "Resource not found")

      {:error, :unauthorized} ->
        send_error(conn, 401, "UNAUTHORIZED", "Unauthorized")

      {:error, reason} when is_binary(reason) ->
        send_error(conn, 500, "INTERNAL_ERROR", reason)

      {:error, _reason} ->
        send_error(conn, 500, "INTERNAL_ERROR", "Internal server error")
    end
  end

  defp validate_input(contract, params) do
    input_schemas = contract.input || []

    with {:ok, validated_params} <- parse_schema(input_schemas[:params], params),
         {:ok, validated_query} <- parse_schema(input_schemas[:query], params),
         {:ok, validated_body} <- parse_schema(input_schemas[:body], params) do
      merged =
        Map.merge(validated_params, validated_query)
        |> Map.merge(validated_body)

      {:ok, merged}
    end
  end

  defp parse_schema(nil, _params), do: {:ok, %{}}

  defp parse_schema(schema, params) do
    case Zoi.parse(schema, params, coerce: true) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, errors} -> {:error, :validation, errors}
    end
  end

  defp call_handler(handler, input, conn) do
    handler.(input, conn)
  end

  defp validate_output(contract, result) do
    case Zoi.parse(contract.output, result) do
      {:ok, output} -> {:ok, output}
      {:error, errors} -> {:error, :validation, errors}
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp send_error(conn, status, code, message) do
    body = %{code: code, message: message}
    send_json(conn, status, body)
  end

  defp send_error(conn, status, code, message, data) do
    body = %{code: code, message: message, data: data}
    send_json(conn, status, body)
  end
end
