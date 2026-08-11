defmodule ElvenGard.Playtest.Feature.Timeout do
  @moduledoc false

  @type attributes ::
          nil
          | Keyword.t()
          | [Keyword.t()]
          | %{optional(:timeout) => timeout()}

  ## Public API

  @spec resolve(attributes(), attributes(), timeout()) :: timeout()
  def resolve(test_attributes, module_attributes, default) do
    timeout_from(test_attributes) || timeout_from(module_attributes) || default
  end

  ## Private functions

  defp timeout_from(nil), do: nil
  defp timeout_from(%{} = attributes), do: Map.get(attributes, :timeout)

  defp timeout_from(attributes) when is_list(attributes) do
    if Keyword.keyword?(attributes) do
      Keyword.get(attributes, :timeout)
    else
      Enum.find_value(attributes, &timeout_from/1)
    end
  end
end
