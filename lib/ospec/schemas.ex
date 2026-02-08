defmodule Ospec.Schemas do
  @moduledoc """
  Built-in reusable schemas for common API patterns.
  """

  @doc """
  Standard error response schema.

      %{error: "not found", details: %{field: "id"}}
  """
  def error do
    Zoi.map(
      %{
        error: Zoi.string(),
        details: Zoi.map() |> Zoi.optional()
      },
      metadata: [ref: :Error]
    )
  end
end
