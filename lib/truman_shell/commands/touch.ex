defmodule TrumanShell.Commands.Touch do
  @moduledoc """
  Handler for the `touch` command - create empty files or update timestamps.

  Returns `{:ok, ""}` on success (silent like bash touch).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Commands.Context
  alias TrumanShell.DomePath
  alias TrumanShell.Posix.Errors
  alias TrumanShell.Support.Sandbox

  @doc """
  Creates an empty file or updates timestamp within the sandbox.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> sandbox = Path.join([File.cwd!(), "tmp", "touch_doctest_#{System.unique_integer([:positive])}"])
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      iex> ctx = %Context{current_path: sandbox, sandbox_config: config}
      iex> {:ok, ""} = TrumanShell.Commands.Touch.handle(["testfile.txt"], ctx)
      iex> File.exists?(Path.join(sandbox, "testfile.txt"))
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle([file_name | _rest], %Context{} = ctx) do
    target = DomePath.expand(file_name, ctx.current_path)
    target_rel = DomePath.relative_to(target, ctx.sandbox_config.home_path)

    case Sandbox.validate_path(target_rel, ctx.sandbox_config) do
      {:ok, safe_path} ->
        case File.touch(safe_path) do
          :ok -> {:ok, ""}
          {:error, reason} -> {:error, "touch: #{file_name}: #{Errors.to_message(reason)}\n"}
        end

      {:error, :outside_sandbox} ->
        {:error, "touch: #{file_name}: No such file or directory\n"}
    end
  end

  def handle([], _ctx) do
    {:error, "touch: missing file operand\n"}
  end
end
