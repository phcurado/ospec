defmodule Ospec.OpenAPI.Swagger do
  @moduledoc """
  Plug for serving Swagger UI.

      # In your router
      get "/api/openapi", Ospec.OpenAPI.Spec, api_spec: MyAppWeb.ApiSpec
      forward "/docs", Ospec.OpenAPI.Swagger, path: "/api/openapi"
  """

  @behaviour Plug

  @impl true
  def init(opts) do
    %{path: Keyword.fetch!(opts, :path)}
  end

  @impl true
  def call(conn, %{path: path}) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, swagger_html(path))
  end

  defp swagger_html(spec_path) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>API Documentation</title>
      <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5.31.0/swagger-ui.css">
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5.31.0/swagger-ui-bundle.js"></script>
      <script>
        SwaggerUIBundle({
          url: "#{spec_path}",
          dom_id: '#swagger-ui'
        });
      </script>
    </body>
    </html>
    """
  end
end
