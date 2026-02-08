defmodule Ospec.Conn do
  @moduledoc """
  Connection helpers for Ospec.

      def index(conn, _params) do
        input = Ospec.Conn.get_input(conn)
        users = MyApp.Accounts.list_users(input.query)
        Ospec.Conn.json(conn, users)
      end
  """

  import Plug.Conn
  require Logger

  @doc """
  Gets the validated input from the connection.

  Returns a map with `:params`, `:query`, and `:body` keys.
  """
  @spec get_input(Plug.Conn.t()) :: %{params: map(), query: map(), body: map()}
  def get_input(conn) do
    conn.private[:ospec_input] || %{params: %{}, query: %{}, body: %{}}
  end

  @doc """
  Gets the current Ospec spec from the connection.
  """
  @spec get_spec(Plug.Conn.t()) :: Ospec.t() | nil
  def get_spec(conn) do
    conn.private[:ospec_spec]
  end

  @doc """
  Validates output against the spec and sends JSON response.

  If output validation fails, logs the error and returns 500.
  """
  @spec json(Plug.Conn.t(), term(), integer()) :: Plug.Conn.t()
  def json(conn, data, status \\ 200)

  def json(%{private: %{ospec_spec: %{output: output}}} = conn, data, status)
      when not is_nil(output) and status in 200..299 do
    coerced_schema = add_coerce(output)

    case Zoi.parse(coerced_schema, data) do
      {:ok, validated} ->
        send_json(conn, status, validated)

      {:error, errors} ->
        Logger.error("Output validation failed: #{inspect(Zoi.treefy_errors(errors))}")
        send_json(conn, 500, %{error: "internal_server_error"})
    end
  end

  def json(conn, data, status) do
    send_json(conn, status, data)
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp add_coerce(%Zoi.Types.Array{inner: inner} = schema) do
    %{schema | inner: add_coerce(inner)}
  end

  defp add_coerce(%Zoi.Types.Map{} = schema) do
    schema
    |> Zoi.Schema.traverse(&Zoi.coerce/1)
    |> Zoi.coerce()
  end

  defp add_coerce(schema), do: schema
end
