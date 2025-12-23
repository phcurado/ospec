defmodule Ospec.TestAPIClient do
  @moduledoc false

  use Ospec.Client,
    base_url: "http://localhost:4000/api",
    headers: %{"x-test" => "true"},
    contracts: Ospec.TestContract.contracts()
end
