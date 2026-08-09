defmodule ElvenGard.Playtest.Options do
  @moduledoc false

  ## Public API

  @spec encode(Keyword.t()) :: map()
  def encode(options) do
    Map.new(options, fn {key, value} -> {Atom.to_string(key), encode_value(value)} end)
  end

  ## Private functions

  defp encode_value(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), encode_value(item)} end)
  end

  defp encode_value(value) when is_list(value), do: Enum.map(value, &encode_value/1)
  defp encode_value(value) when is_boolean(value) or is_nil(value), do: value
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(value), do: value
end
