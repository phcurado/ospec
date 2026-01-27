defmodule Ospec.HTTP do
  @moduledoc """
  HTTP response helpers for Ospec handlers.

  The data passed to success helpers (like `ok/1` and `created/1`) is validated
  against the endpoint's output schema before sending.

  ## Example

      |> Ospec.handler(fn ctx, input ->
        case MyApp.Accounts.get_user(input.params.id) do
          nil -> Ospec.HTTP.not_found()
          user -> Ospec.HTTP.ok(user)
        end
      end)

  ## Custom Status Codes

  For status codes without a dedicated helper, use `status/2`:

      Ospec.HTTP.status(410, %{message: "Resource has been removed"})
      Ospec.HTTP.status(303, nil)
  """

  defmodule Response do
    @moduledoc false

    @type t :: %__MODULE__{
            status: atom(),
            data: term()
          }

    defstruct [:status, :data]
  end

  # Success responses (2xx)

  @doc """
  Returns a 200 OK response with the given data.

  The data will be validated against the endpoint's output schema.
  """
  @spec ok(term()) :: Response.t()
  def ok(data) do
    %Response{status: :ok, data: data}
  end

  @doc """
  Returns a 201 Created response with the given data.

  The data will be validated against the endpoint's output schema.
  """
  @spec created(term()) :: Response.t()
  def created(data) do
    %Response{status: :created, data: data}
  end

  @doc """
  Returns a 202 Accepted response with optional data.
  """
  @spec accepted(term()) :: Response.t()
  def accepted(data \\ nil) do
    %Response{status: :accepted, data: data}
  end

  @doc """
  Returns a 204 No Content response.
  """
  @spec no_content() :: Response.t()
  def no_content do
    %Response{status: :no_content, data: nil}
  end

  # Client error responses (4xx)

  @doc """
  Returns a 400 Bad Request response with optional error details.
  """
  @spec bad_request(term()) :: Response.t()
  def bad_request(data \\ nil) do
    %Response{status: :bad_request, data: data}
  end

  @doc """
  Returns a 401 Unauthorized response.
  """
  @spec unauthorized() :: Response.t()
  def unauthorized do
    %Response{status: :unauthorized, data: nil}
  end

  @doc """
  Returns a 403 Forbidden response.
  """
  @spec forbidden() :: Response.t()
  def forbidden do
    %Response{status: :forbidden, data: nil}
  end

  @doc """
  Returns a 404 Not Found response.
  """
  @spec not_found() :: Response.t()
  def not_found do
    %Response{status: :not_found, data: nil}
  end

  @doc """
  Returns a 409 Conflict response with optional error details.
  """
  @spec conflict(term()) :: Response.t()
  def conflict(data \\ nil) do
    %Response{status: :conflict, data: data}
  end

  @doc """
  Returns a 422 Unprocessable Entity response with optional error details.
  """
  @spec unprocessable_entity(term()) :: Response.t()
  def unprocessable_entity(data \\ nil) do
    %Response{status: :unprocessable_entity, data: data}
  end

  @doc """
  Returns a 429 Too Many Requests response.
  """
  @spec too_many_requests() :: Response.t()
  def too_many_requests do
    %Response{status: :too_many_requests, data: nil}
  end

  # Server error responses (5xx)

  @doc """
  Returns a 500 Internal Server Error response.
  """
  @spec internal_server_error() :: Response.t()
  def internal_server_error do
    %Response{status: :internal_server_error, data: nil}
  end

  @doc """
  Returns a 503 Service Unavailable response.
  """
  @spec service_unavailable() :: Response.t()
  def service_unavailable do
    %Response{status: :service_unavailable, data: nil}
  end

  # Generic helper

  @doc """
  Returns a response with a custom status code and optional data.

  ## Examples

      Ospec.HTTP.status(303, nil)
      Ospec.HTTP.status(410, %{message: "Resource has been removed"})
  """
  @spec status(integer(), term()) :: Response.t()
  def status(status, data \\ nil) do
    %Response{status: status, data: data}
  end
end
