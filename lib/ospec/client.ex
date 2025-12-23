defmodule Ospec.Client do
  @moduledoc """
  Type-safe HTTP client for Ospec contracts.

  The client validates input before sending and validates output on response,
  ensuring end-to-end type safety.

  ## Requirements

  Add `{:req, "~> 0.5"}` to your dependencies to use this module.

  ## Module-based Usage

  First, define your contracts with a `contracts/0` function:

      defmodule MyAPI.Contract do
        @user Zoi.object(%{id: Zoi.integer(), name: Zoi.string()}, coerce: true)

        def contracts do
          %{
            list_users:
              Ospec.new()
              |> Ospec.route(method: :get, path: "/users")
              |> Ospec.input(query: Zoi.object(%{page: Zoi.integer() |> Zoi.default(1)}, coerce: true))
              |> Ospec.output(Zoi.array(@user)),

            find_user:
              Ospec.new()
              |> Ospec.route(method: :get, path: "/users/:id")
              |> Ospec.input(params: Zoi.object(%{id: Zoi.integer()}, coerce: true))
              |> Ospec.output(@user)
          }
        end
      end

  Then create a client module that auto-generates functions:

      defmodule MyApp.APIClient do
        use Ospec.Client,
          base_url: "http://localhost:4000/api",
          headers: %{"authorization" => "Bearer token"},
          contracts: MyAPI.Contract.contracts()
      end

      # Auto-generates functions from contracts:
      {:ok, users} = MyApp.APIClient.list_users(%{page: 1})
      {:ok, user} = MyApp.APIClient.find_user(%{id: 123})
      user = MyApp.APIClient.find_user!(%{id: 123})  # raises on error

  ## Functional Usage

  For more control, use the functional API directly:

      client = Ospec.Client.new(base_url: "http://localhost:4000/api")
      {:ok, users} = Ospec.Client.call(client, MyAPI.Contract.contracts().list_users, %{page: 1})

  ## Options

  - `:base_url` - Base URL for all requests (required)
  - `:headers` - Default headers for all requests (default: %{})
  - `:req_options` - Additional options passed to Req (default: [])
  - `:contracts` - Contracts map from `MyContract.contracts()` (for module-based usage)

  ## Error Handling

  Returns `{:ok, result}` on success or `{:error, reason}` on failure:

      case MyApp.APIClient.find_user(%{id: 123}) do
        {:ok, user} -> # Handle success
        {:error, %Ospec.Client.ValidationError{}} -> # Input/output validation failed
        {:error, %Ospec.Client.RequestError{}} -> # HTTP request failed
        {:error, %Ospec.Client.ServerError{}} -> # Server returned error response
      end
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @base_url Keyword.fetch!(opts, :base_url)
      @headers Keyword.get(opts, :headers, %{})
      @req_options Keyword.get(opts, :req_options, [])
      @contracts Keyword.fetch!(opts, :contracts)

      @doc """
      Returns the configured client.
      """
      def client() do
        Ospec.Client.new(
          base_url: @base_url,
          headers: @headers,
          req_options: @req_options
        )
      end

      for {func_name, contract} <- @contracts do
        @contract contract

        @doc """
        Calls the `#{func_name}` endpoint.

        Returns `{:ok, result}` on success or `{:error, reason}` on failure.
        """
        def unquote(func_name)(input \\ %{}) do
          Ospec.Client.call(client(), @contract, input)
        end

        @doc """
        Same as `#{func_name}/1` but raises on error.
        """
        def unquote(:"#{func_name}!")(input \\ %{}) do
          Ospec.Client.call!(client(), @contract, input)
        end
      end
    end
  end

  defmodule ValidationError do
    @moduledoc "Raised when input or output validation fails."
    defexception [:message, :errors, :phase]

    @type t :: %__MODULE__{message: binary(), errors: term(), phase: :input | :output}

    @impl true
    def message(%{message: message}), do: message
  end

  defmodule RequestError do
    @moduledoc "Raised when HTTP request fails."
    defexception [:message, :reason]

    @type t :: %__MODULE__{message: binary(), reason: term()}

    @impl true
    def message(%{message: message}), do: message
  end

  defmodule ServerError do
    @moduledoc "Raised when server returns an error response."
    defexception [:message, :status, :code, :data]

    @type t :: %__MODULE__{
            message: binary(),
            status: integer(),
            code: binary() | nil,
            data: term()
          }

    @impl true
    def message(%{message: message}), do: message
  end

  @client_schema Zoi.object(
                   %{
                     base_url: Zoi.string(),
                     headers: Zoi.map(Zoi.string(), Zoi.string()) |> Zoi.default(%{}),
                     req_options: Zoi.keyword(Zoi.any()) |> Zoi.default([])
                   },
                   coerce: true
                 )

  @type t :: %__MODULE__{
          base_url: binary(),
          headers: map(),
          req_options: keyword()
        }

  defstruct [:base_url, :headers, :req_options]

  @doc """
  Creates a new client.

  ## Options

  - `:base_url` - Base URL for all requests (required)
  - `:headers` - Default headers for all requests (default: %{})
  - `:req_options` - Additional options passed to Req (default: [])

  ## Examples

      client = Ospec.Client.new(base_url: "http://localhost:4000/api")

      client = Ospec.Client.new(
        base_url: "http://localhost:4000/api",
        headers: %{"authorization" => "Bearer token"}
      )
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    parsed = Zoi.parse!(@client_schema, Map.new(opts))

    struct!(__MODULE__, Map.to_list(parsed))
  end

  @doc """
  Calls an RPC endpoint using a contract.

  1. Validates input against the contract's input schema
  2. Builds the URL from route and path params
  3. Makes HTTP request with query params or JSON body
  4. Validates response against the contract's output schema

  ## Examples

      {:ok, users} = Ospec.Client.call(client, MyAPI.Contract.list_users(), %{page: 1})
      {:ok, user} = Ospec.Client.call(client, MyAPI.Contract.find_user(), %{id: 123})
  """
  @spec call(t(), Ospec.t(), map()) ::
          {:ok, term()} | {:error, ValidationError.t() | RequestError.t() | ServerError.t()}
  def call(client, contract, input \\ %{}) do
    with {:ok, validated_input} <- validate_input(contract, input),
         {:ok, response} <- make_request(client, contract, validated_input) do
      handle_response(contract, response)
    end
  end

  @doc """
  Same as `call/3` but raises on error.
  """
  @spec call!(t(), Ospec.t(), map()) :: term()
  def call!(client, contract, input \\ %{}) do
    case call(client, contract, input) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp validate_input(contract, input) do
    input_schemas = contract.input || []

    with {:ok, validated_params} <- parse_input_schema(input_schemas[:params], input),
         {:ok, validated_query} <- parse_input_schema(input_schemas[:query], input),
         {:ok, validated_body} <- parse_input_schema(input_schemas[:body], input) do
      {:ok,
       %{
         params: validated_params,
         query: validated_query,
         body: validated_body
       }}
    end
  end

  defp parse_input_schema(nil, _input), do: {:ok, %{}}

  defp parse_input_schema(schema, input) do
    case Zoi.parse(schema, input, coerce: true) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, errors} ->
        {:error,
         %ValidationError{
           message: "Input validation failed",
           errors: errors,
           phase: :input
         }}
    end
  end

  defp make_request(client, contract, validated_input) do
    ensure_req_available!()

    route = contract.route
    url = build_url(client.base_url, route[:path], validated_input.params)
    method = route[:method]

    req_opts =
      client.req_options
      |> Keyword.merge(
        url: url,
        method: method,
        headers: Map.to_list(client.headers)
      )
      |> add_query_params(validated_input.query)
      |> add_body(validated_input.body)

    case Req.request(req_opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error,
         %RequestError{
           message: "HTTP request failed: #{inspect(reason)}",
           reason: reason
         }}
    end
  end

  defp ensure_req_available! do
    unless Code.ensure_loaded?(Req) do
      raise "Req is required for Ospec.Client. Add {:req, \"~> 0.5\"} to your dependencies."
    end
  end

  defp build_url(base_url, path, params) do
    path_with_params =
      Enum.reduce(params, path, fn {key, value}, acc ->
        String.replace(acc, ":#{key}", to_string(value))
      end)

    String.trim_trailing(base_url, "/") <> path_with_params
  end

  defp add_query_params(opts, query) when query == %{}, do: opts
  defp add_query_params(opts, query), do: Keyword.put(opts, :params, query)

  defp add_body(opts, body) when body == %{}, do: opts
  defp add_body(opts, body), do: Keyword.put(opts, :json, body)

  defp handle_response(contract, response) do
    case response.status do
      status when status in 200..299 ->
        validate_output(contract, response.body)

      status ->
        handle_error_response(status, response.body)
    end
  end

  defp validate_output(contract, body) do
    case Zoi.parse(contract.output, body, coerce: true) do
      {:ok, result} ->
        {:ok, result}

      {:error, errors} ->
        {:error,
         %ValidationError{
           message: "Output validation failed",
           errors: errors,
           phase: :output
         }}
    end
  end

  defp handle_error_response(status, body) when is_map(body) do
    {:error,
     %ServerError{
       message: body["message"] || "Server error",
       status: status,
       code: body["code"],
       data: body["data"]
     }}
  end

  defp handle_error_response(status, body) do
    {:error,
     %ServerError{
       message: "Server error: #{inspect(body)}",
       status: status,
       code: nil,
       data: nil
     }}
  end
end
