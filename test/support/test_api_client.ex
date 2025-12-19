defmodule Zoi.RPC.TestAPIClient do
  @moduledoc false

  use Zoi.RPC.Client,
    base_url: "http://localhost:4000/api",
    headers: %{"x-test" => "true"},
    contracts: Zoi.RPC.TestContract.contracts()
end
