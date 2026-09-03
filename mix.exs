defmodule Fltr.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/austinthecoder/ex-fltr"

  def project do
    [
      app: :fltr,
      version: @version,
      elixir: "~> 1.14",
      description:
        "Composable, reusable filters for Ecto queries with optional external input parsing.",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @source_url},
        files: ~w(lib mix.exs README.md LICENSE)
      ],
      source_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_ref: "v#{@version}"
      ],
      deps: [
        {:ecto, System.get_env("FLTR_ECTO_VERSION", "~> 3.10")},
        {:ex_doc, "~> 0.40", only: :dev, runtime: false}
      ]
    ]
  end

  def application do
    []
  end
end
