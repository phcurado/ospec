defmodule Ospec.OpenAPI do
  @moduledoc """
  Generates OpenAPI specification from Ospec controllers.
  """

  @doc """
  Generates OpenAPI spec from an ApiSpec module.
  """
  @spec generate(module()) :: map()
  def generate(api_spec) do
    api_spec.spec()
  end

  @doc """
  Builds OpenAPI paths from discovered controllers.

      Ospec.OpenAPI.paths(:my_app)
      Ospec.OpenAPI.paths(:my_app, pattern: ~r/MyAppWeb\\.\\w+Controller$/)
  """
  @spec paths(atom(), keyword()) :: map()
  def paths(app, opts \\ []) do
    pattern = opts[:pattern]

    app
    |> discover_controllers(pattern)
    |> Enum.flat_map(fn c ->
      Enum.map(c.__ospec_specs__(), fn {action, spec} -> {c, action, spec} end)
    end)
    |> Enum.reduce(%{}, fn {controller, action, spec}, acc ->
      {method, path} = spec.route
      operation = build_operation(controller, action, spec)
      methods = Map.put(acc[path] || %{}, to_string(method), operation)
      Map.put(acc, path, methods)
    end)
  end

  @doc """
  Builds OpenAPI components section from schemas with `ref` metadata.

  Can auto-discover from app controllers or accept explicit list:

      Ospec.OpenAPI.components(:my_app)
      Ospec.OpenAPI.components([MyApp.Schemas.user(), MyApp.Schemas.error()])
  """
  def components(app) when is_atom(app) do
    schemas = discover_schemas(app)
    build_components(schemas)
  end

  def components(schemas) when is_list(schemas) do
    build_components(schemas)
  end

  defp build_components(schemas) do
    component_schemas =
      schemas
      |> Enum.filter(&Zoi.metadata(&1)[:ref])
      |> Enum.uniq_by(&Zoi.metadata(&1)[:ref])
      |> Map.new(fn schema ->
        name = Zoi.metadata(schema)[:ref]
        {to_string(name), Zoi.to_json_schema(schema)}
      end)

    %{schemas: component_schemas}
  end

  defp discover_schemas(app) do
    app
    |> discover_controllers(nil)
    |> Enum.flat_map(fn controller ->
      controller.__ospec_specs__()
      |> Map.values()
      |> Enum.flat_map(&extract_schemas/1)
    end)
  end

  defp extract_schemas(spec) do
    schemas = []
    schemas = if spec.output, do: [spec.output | schemas], else: schemas
    schemas = if spec.input[:body], do: [spec.input[:body] | schemas], else: schemas

    schemas =
      if spec.responses do
        spec.responses |> Map.values() |> Enum.concat(schemas)
      else
        schemas
      end

    Enum.flat_map(schemas, &collect_refs/1)
  end

  defp collect_refs(%Zoi.Types.Array{inner: inner} = schema) do
    if Zoi.metadata(schema)[:ref] do
      [schema | collect_refs(inner)]
    else
      collect_refs(inner)
    end
  end

  defp collect_refs(%Zoi.Types.Map{fields: fields} = schema) when is_list(fields) do
    nested = Enum.flat_map(fields, fn {_name, field} -> collect_refs(field) end)

    if Zoi.metadata(schema)[:ref] do
      [schema | nested]
    else
      nested
    end
  end

  defp collect_refs(schema) do
    if Zoi.metadata(schema)[:ref], do: [schema], else: []
  end

  @spec discover_controllers(atom(), Regex.t() | nil) :: [module()]
  defp discover_controllers(app, pattern) do
    modules =
      case Application.spec(app, :modules) do
        nil ->
          []

        mods ->
          Enum.filter(mods, fn mod ->
            Code.ensure_loaded(mod)
            function_exported?(mod, :__ospec_specs__, 0)
          end)
      end

    case pattern do
      nil -> modules
      regex -> Enum.filter(modules, fn m -> Regex.match?(regex, to_string(m)) end)
    end
  end

  defp build_operation(_controller, _action, spec) do
    %{}
    |> maybe_add(:tags, spec.tags)
    |> maybe_add(:summary, spec.summary)
    |> maybe_add(:description, spec.description)
    |> maybe_add_parameters(spec.input[:params], "path")
    |> maybe_add_parameters(spec.input[:query], "query")
    |> maybe_add_request_body(spec.input[:body])
    |> add_responses(spec)
  end

  defp maybe_add_parameters(op, nil, _), do: op

  defp maybe_add_parameters(op, schema, location) do
    params =
      Enum.map(schema.fields, fn {name, field} ->
        %{
          name: to_string(name),
          in: location,
          required: field.meta.required != false,
          schema: Zoi.to_json_schema(field)
        }
        |> maybe_add(:description, Zoi.description(field))
      end)

    Map.update(op, :parameters, params, &(&1 ++ params))
  end

  defp maybe_add_request_body(op, nil), do: op

  defp maybe_add_request_body(op, schema) do
    Map.put(op, :requestBody, %{
      required: true,
      content: %{"application/json" => %{schema: schema_or_ref(schema)}}
    })
  end

  defp add_responses(op, %{output: nil, responses: nil}) do
    Map.put(op, :responses, %{"200" => %{description: "Success"}})
  end

  defp add_responses(op, %{output: output, responses: responses}) do
    base = if output, do: %{200 => output}, else: %{}
    all_responses = Map.merge(base, responses || %{})

    formatted =
      Map.new(all_responses, fn {status, schema} ->
        {to_string(status),
         %{
           description: status_description(status),
           content: %{"application/json" => %{schema: schema_or_ref(schema)}}
         }}
      end)

    Map.put(op, :responses, formatted)
  end

  defp status_description(200), do: "Success"
  defp status_description(201), do: "Created"
  defp status_description(204), do: "No Content"
  defp status_description(400), do: "Bad Request"
  defp status_description(401), do: "Unauthorized"
  defp status_description(403), do: "Forbidden"
  defp status_description(404), do: "Not Found"
  defp status_description(422), do: "Unprocessable Entity"
  defp status_description(500), do: "Internal Server Error"
  defp status_description(_), do: "Response"

  defp schema_or_ref(schema) do
    to_json_schema(schema)
  end

  defp to_json_schema(schema) do
    case Zoi.metadata(schema)[:ref] do
      nil -> encode_with_refs(schema)
      name -> %{"$ref" => "#/components/schemas/#{name}"}
    end
  end

  defp encode_with_refs(%Zoi.Types.Array{} = schema) do
    Zoi.to_json_schema(schema)
    |> Map.put(:items, to_json_schema(schema.inner))
  end

  defp encode_with_refs(%Zoi.Types.Map{} = schema) do
    base = Zoi.to_json_schema(schema)

    properties =
      Map.new(schema.fields, fn {name, field} ->
        {to_string(name), to_json_schema(field)}
      end)

    Map.put(base, :properties, properties)
  end

  defp encode_with_refs(schema) do
    Zoi.to_json_schema(schema)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
