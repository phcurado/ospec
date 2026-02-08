defmodule Mix.Tasks.Ospec.Openapi do
  @moduledoc """
  Generates an OpenAPI specification file.

      mix ospec.openapi MyApp.ApiSpec
      mix ospec.openapi MyApp.ApiSpec --output openapi.json

  ## Options

    * `--output` - Output file path (default: openapi.json)
  """

  use Mix.Task

  @shortdoc "Generates OpenAPI specification"

  @impl true
  def run(args) do
    Mix.Task.run("compile")

    {opts, args} = OptionParser.parse!(args, strict: [output: :string])
    output = opts[:output] || "openapi.json"

    case args do
      [api_spec_module] ->
        module = Module.concat([api_spec_module])
        spec = Ospec.OpenAPI.generate(module)
        json = Jason.encode!(spec, pretty: true)

        File.write!(output, json)
        Mix.shell().info("Generated #{output}")

      [] ->
        Mix.shell().error("Usage: mix ospec.openapi MyApp.ApiSpec [--output FILE]")

      _ ->
        Mix.shell().error("Too many arguments")
    end
  end
end
