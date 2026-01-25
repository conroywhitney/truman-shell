defmodule TrumanShell.MixProject do
  use Mix.Project

  def project do
    [
      app: :truman_shell,
      version: "0.4.2",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      description: "A simulated shell environment for AI agents",
      package: package(),
      dialyzer: dialyzer(),
      test_coverage: [
        ignore_modules: [TrumanShell.CLI],
        threshold: 90.0
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
      # YAML parsing for agents.yaml config
      {:yaml_elixir, "~> 2.11"},
      # Dev/test only
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:styler, "~> 1.10", only: [:dev, :test], runtime: false},
      {:tallarium_credo, "~> 0.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp escript do
    [
      main_module: TrumanShell.CLI,
      path: "dist/truman-shell"
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts/core.plt",
      plt_local_path: "priv/plts/project.plt",
      plt_add_apps: [:mix],
      flags: [:error_handling, :underspecs],
      # Exclude credo checks (Credo is dev dependency, dialyzer can't see it)
      exclude_modules: [TrumanShell.Credo.NoRawPathCalls]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/conroywhitney/truman-shell"}
    ]
  end
end
