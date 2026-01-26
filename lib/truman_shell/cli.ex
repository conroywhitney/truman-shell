defmodule TrumanShell.CLI do
  @moduledoc """
  CLI entry point for TrumanShell escript and bin/truman-shell.

  ## Subcommands

      truman-shell execute <command>    Execute a shell command through TrumanShell
      truman-shell validate-path <path> Validate path is within sandbox allowed_paths
      truman-shell version              Show version

  ## Exit codes

  - `0` — Success (output on stdout)
  - `1` — Error (message on stderr, or silent for validate-path deny)

  ## Configuration

  Sandbox `allowed_paths` and `home_path` are loaded from agents.yaml.
  See `TrumanShell.Config` for discovery order and defaults.
  """

  alias TrumanShell.Commands.Context
  alias TrumanShell.Config
  alias TrumanShell.Support.Sandbox

  # All private functions call System.halt/1, which is no_return
  @dialyzer {:no_return,
             execute: 1,
             validate: 1,
             handle_version: 0,
             handle_usage: 0}

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    case argv do
      ["execute", command | _] -> execute(command)
      ["execute"] -> handle_usage()
      ["validate-path", path | _] -> validate(path)
      ["validate-path"] -> handle_usage()
      ["version"] -> handle_version()
      _ -> handle_usage()
    end
  end

  defp execute(command) do
    Application.ensure_all_started(:truman_shell)

    case TrumanShell.execute(command) do
      {:ok, output, _ctx} ->
        IO.write(output)
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp validate(path) do
    # Load config from agents.yaml (or defaults)
    case Config.discover() do
      {:ok, config} ->
        # Build context from config (respects YAML-defined sandbox)
        ctx = Context.from_config(config)

        case Sandbox.validate_path(path, ctx) do
          {:ok, resolved_path} ->
            IO.puts(resolved_path)
            System.halt(0)

          {:error, _reason} ->
            # 404 principle: silent deny (no stdout, no stderr)
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error loading config: #{reason}")
        System.halt(1)
    end
  end

  defp handle_version do
    {:ok, vsn} = :application.get_key(:truman_shell, :vsn)
    IO.puts(List.to_string(vsn))
    System.halt(0)
  end

  defp handle_usage do
    IO.puts(:stderr, """
    Usage: truman-shell <command> [args]

    Commands:
      execute <shell-command>   Execute a command through TrumanShell
      validate-path <path>      Validate path is within sandbox allowed_paths
      version                   Show version

    Configuration:
      Sandbox allowed_paths and home_path are loaded from agents.yaml.
      See TrumanShell.Config for discovery order and defaults.
    """)

    System.halt(1)
  end
end
