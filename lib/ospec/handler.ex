defmodule Ospec.Handler do
  @moduledoc """
  Server-side request handling for Ospec contracts.

  This module validates incoming requests against contract schemas, executes your handler function,
  and validates the response before sending it back. Input is automatically extracted from the
  appropriate `conn` fields based on the contract's input schema (`:params` from `conn.path_params`,
  `:query` from `conn.query_params`, `:body` from `conn.body_params`).

      defmodule MyAppWeb.UsersController do
        use MyAppWeb, :controller

        def list(conn, _params) do
          Ospec.handle(conn, MyAPI.list_users(), fn input, _conn ->
            users = MyApp.Account.list_users(%{page: input.page, page_size: input.page_size})
            {:ok, users}
          end)
        end
      end

  The handler function receives the validated input and the conn, and should return
  `{:ok, result}` or `{:error, reason}`. Common error atoms like `:not_found` and `:unauthorized`
  are automatically mapped to appropriate HTTP status codes.

  Input validation errors return 422, while output validation errors return 500 since they
  indicate a server bug (the response doesn't match the contract).
  """

  import Plug.Conn

  @doc """
  Handles an HTTP request using a contract.

  Validates input from conn, calls the handler, validates output, and sends the JSON response.
  """
  def handle(conn, contract, handler) do
    with {:ok, input} <- validate_input(contract, conn),
         {:ok, result} <- call_handler(handler, input, conn),
         {:ok, output} <- validate_output(contract, result) do
      send_json(conn, 200, output)
    else
      {:error, :input_validation, errors} ->
        tree = Zoi.treefy_errors(errors)
        send_error(conn, 422, "VALIDATION_ERROR", "Validation failed", tree)

      {:error, :output_validation, errors} ->
        tree = Zoi.treefy_errors(errors)
        send_error(conn, 500, "OUTPUT_VALIDATION_ERROR", "Response validation failed", tree)

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

  defp validate_input(contract, conn) do
    input_schemas = contract.input || []

    with {:ok, validated_params} <- parse_schema(input_schemas[:params], conn.path_params),
         {:ok, validated_query} <- parse_schema(input_schemas[:query], conn.query_params),
         {:ok, validated_body} <- parse_schema(input_schemas[:body], conn.body_params) do
      merged =
        Map.merge(validated_params, validated_query)
        |> Map.merge(validated_body)

      {:ok, merged}
    end
  end

  defp parse_schema(nil, _data), do: {:ok, %{}}

  defp parse_schema(schema, data) do
    case Zoi.parse(schema, data, coerce: true) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, errors} -> {:error, :input_validation, errors}
    end
  end

  defp call_handler(handler, input, conn) do
    handler.(input, conn)
  end

  defp validate_output(%{output: nil}, result), do: {:ok, result}

  defp validate_output(contract, result) do
    case Zoi.parse(contract.output, result) do
      {:ok, output} -> {:ok, output}
      {:error, errors} -> {:error, :output_validation, errors}
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
