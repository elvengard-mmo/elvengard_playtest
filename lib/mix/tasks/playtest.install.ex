defmodule Mix.Tasks.Playtest.Install do
  @moduledoc """
  Installs Playtest's pinned Node sidecar dependencies and browser binaries.

      mix playtest.install
      mix playtest.install --browser firefox
      mix playtest.install --browser all
      mix playtest.install --with-deps
      mix playtest.install --skip-browser

  Installation happens in the user cache and never creates `package.json`, a
  lockfile or `node_modules` in the consuming application.
  """

  use Mix.Task

  alias ElvenGard.Playtest.Installation

  @shortdoc "Installs the pinned Playwright runtime used by Playtest"
  @switches [browser: :string, skip_browser: :boolean, with_deps: :boolean]

  ## Mix.Task callbacks

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)
    validate_args!(positional, invalid)

    cache_dir = Installation.cache_dir()
    manifests = Installation.manifest_paths()
    File.mkdir_p!(cache_dir)
    File.cp!(manifests.package, Path.join(cache_dir, "package.json"))
    File.cp!(manifests.lock, Path.join(cache_dir, "package-lock.json"))

    npm = System.find_executable("npm") || Mix.raise("Playtest installation requires npm")
    run_command!(npm, ["ci", "--ignore-scripts"], cache_dir, "install_node_dependencies")

    unless opts[:skip_browser] do
      browser = Keyword.get(opts, :browser, "chromium")
      install_browsers!(cache_dir, browser, opts[:with_deps] || false)
    end

    Mix.shell().info("Playtest runtime installed in #{cache_dir}")
  end

  ## Private functions

  defp validate_args!([], []), do: :ok

  defp validate_args!(positional, invalid) do
    Mix.raise(
      "Invalid playtest.install arguments: positional=#{inspect(positional)} invalid=#{inspect(invalid)}"
    )
  end

  defp install_browsers!(cache_dir, "all", with_deps?) do
    install_browsers!(cache_dir, "chromium firefox webkit", with_deps?)
  end

  defp install_browsers!(cache_dir, browsers, with_deps?) do
    executable = Path.join([cache_dir, "node_modules", ".bin", "playwright"])

    arguments =
      ["install"] ++ if(with_deps?, do: ["--with-deps"], else: []) ++ String.split(browsers)

    run_command!(executable, arguments, cache_dir, "install_browsers")
  end

  defp run_command!(executable, arguments, directory, stage) do
    case System.cmd(executable, arguments, cd: directory, stderr_to_stdout: true) do
      {output, 0} ->
        if output != "", do: Mix.shell().info(output)

      {output, status} ->
        Mix.raise(
          "Playtest installation failed during #{stage}: " <>
            "status=#{status} detail=#{String.slice(output, 0, 2_000)}"
        )
    end
  end
end
