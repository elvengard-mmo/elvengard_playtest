defmodule ElvenGard.Playtest.Feature.ConfigurationTest do
  use ExUnit.Case, async: true

  defmodule ConfiguredFeature do
    use ElvenGard.Playtest.Feature,
      async: true,
      group: :shared_browser_resource,
      players: [],
      feature_timeout: 120_000

    def feature_timeout(), do: @elvengard_playtest_feature_timeout
  end

  test "persists the feature timeout configured when the case is used" do
    assert ConfiguredFeature.feature_timeout() == 120_000
  end

  test "forwards the ExUnit group used to isolate a shared resource" do
    assert ConfiguredFeature.__ex_unit__(:config).group == :shared_browser_resource
  end

  test "rejects an invalid feature timeout" do
    module = Module.concat(__MODULE__, InvalidFeature)

    assert_raise ArgumentError, ~r/:feature_timeout must be/, fn ->
      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use ElvenGard.Playtest.Feature, players: [], feature_timeout: -1
          end
        end
      )
    end
  end
end
