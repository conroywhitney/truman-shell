defmodule TrumanShell.CLI do
  @moduledoc """
  CLI entry point for TrumanShell escript and bin/truman-shell.

  ## Subcommands

      truman-shell execute <command>                Execute a shell command through TrumanShell
      truman-shell validate-path <path> [<cwd>]     Validate path is within sandbox
      truman-shell version                          Show version

  ## Exit codes

  - `0` — Success (output on stdout)
  - `1` — Error (message on stderr, or silent for validate-path deny)
  """

  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.Support.Sandbox

  # All private functions call System.halt/1, which is no_return
  @dialyzer {:no_return,
             handle_execute: 1,
             execute: 1,
             handle_validate_path: 1,
             validate: 2,
             handle_version: 0,
             handle_usage: 0,
             error: 1}

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    case argv do
      ["execute" | rest] -> handle_execute(rest)
      ["validate-path" | rest] -> handle_validate_path(rest)
      ["version"] -> handle_version()
      _ -> handle_usage()
    end
  end

  defp handle_execute([]) do
    # Support TRUMAN_CMD env var (for shell safety) or direct argument
    case System.get_env("TRUMAN_CMD") do
      nil -> error("No command provided")
      "" -> error("No command provided")
      cmd -> execute(cmd)
    end
  end

  defp handle_execute([command | _]) do
    execute(command)
  end

  defp execute(command) do
    Application.ensure_all_started(:truman_shell)

    case TrumanShell.execute(command) do
      {:ok, output} ->
        IO.write(output)
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp handle_validate_path([]) do
    # Support env var pattern (for shell safety) or direct argument
    case System.get_env("TRUMAN_VALIDATE_PATH") do
      nil -> error("No path provided")
      "" -> error("No path provided")
      path -> validate(path, System.get_env("TRUMAN_CURRENT_DIR"))
    end
  end

  defp handle_validate_path([path]) do
    validate(path, nil)
  end

  defp handle_validate_path([path, current_dir | _]) do
    validate(path, current_dir)
  end

  defp validate(path, current_dir) do
    # Normalize empty string to nil for current_dir fallback
    current_dir = if current_dir in [nil, ""], do: nil, else: current_dir
    sandbox_root = Sandbox.sandbox_root()
    # Build struct-based config for validate_path/2
    default_cwd = current_dir || sandbox_root
    config = %SandboxConfig{roots: [sandbox_root], default_cwd: default_cwd}

    case Sandbox.validate_path(path, config) do
      {:ok, resolved_path} ->
        IO.puts(resolved_path)
        System.halt(0)

      {:error, _reason} ->
        # 404 principle: silent deny (no stdout, no stderr)
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
      execute <shell-command>              Execute a command through TrumanShell
      validate-path <path> [<current_dir>] Validate path is within sandbox
      version                              Show version

    Environment:
      TRUMAN_DOME          Sandbox root directory (default: cwd)
      TRUMAN_CMD           Command for execute (alternative to argument)
      TRUMAN_VALIDATE_PATH Path for validate-path (alternative to argument)
      TRUMAN_CURRENT_DIR   Current directory for validate-path (optional)
    """)

    System.halt(1)
  end

  defp error(message) do
    IO.puts(:stderr, "Error: #{message}")
    System.halt(1)
  end
end
