defmodule Ospec.OpenAPI.Spec do
  @moduledoc """
  Plug for serving the OpenAPI spec as JSON.

      # In your router
      get "/api/openapi", Ospec.OpenAPI.Spec, api_spec: MyAppWeb.ApiSpec
  """

  @behaviour Plug

  @impl true
  def init(opts) do
    %{api_spec: Keyword.fetch!(opts, :api_spec)}
  end

  @impl true
  def call(conn, %{api_spec: api_spec}) do
    spec = Ospec.OpenAPI.generate(api_spec)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(spec))
  end
end
