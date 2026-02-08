defmodule Ospec.Plug do
  @moduledoc """
  Plug that validates request input against Ospec specs.

  Automatically added when you `use Ospec.Controller`.
  Validates input before the action runs and stores it for `Ospec.Conn.get_input/1`.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    controller = conn.private.phoenix_controller
    action = conn.private.phoenix_action
    specs = controller.__ospec_specs__()

    case specs[action] do
      nil -> conn
      spec -> validate_input(conn, spec)
    end
  end

  defp validate_input(conn, spec) do
    input_schemas = spec.input || []

    with {:ok, params} <- parse_schema(input_schemas[:params], conn.path_params),
         {:ok, query} <- parse_schema(input_schemas[:query], conn.query_params),
         {:ok, body} <- parse_schema(input_schemas[:body], conn.body_params) do
      validated_input = %{
        params: params,
        query: query,
        body: body
      }

      conn
      |> put_private(:ospec_input, validated_input)
      |> put_private(:ospec_spec, spec)
    else
      {:error, errors} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          422,
          Jason.encode!(%{
            error: "validation_error",
            details: Zoi.treefy_errors(errors)
          })
        )
        |> halt()
    end
  end

  defp parse_schema(nil, _data), do: {:ok, %{}}

  defp parse_schema(schema, data) do
    Zoi.parse(schema, data, coerce: true)
  end
end
