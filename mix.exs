defmodule Ospec.MixProject do
  use Mix.Project

  def project do
    [
      app: :ospec,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:zoi, "~> 0.14"},
      {:plug, "~> 1.19"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5", optional: true},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end
end
