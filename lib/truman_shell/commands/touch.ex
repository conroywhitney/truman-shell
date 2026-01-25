defmodule TrumanShell.Commands.Touch do
  @moduledoc """
  Handler for the `touch` command - create empty files or update timestamps.

  Returns `{:ok, ""}` on success (silent like bash touch).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.DomePath
  alias TrumanShell.Posix.Errors
  alias TrumanShell.Support.Sandbox

  @doc """
  Creates an empty file or updates timestamp within the sandbox.

  ## Examples

      iex> sandbox = Path.join([File.cwd!(), "tmp", "touch_doctest_#{System.unique_integer([:positive])}"])
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> context = %{sandbox_root: sandbox, current_dir: sandbox}
      iex> {:ok, ""} = TrumanShell.Commands.Touch.handle(["testfile.txt"], context)
      iex> File.exists?(Path.join(sandbox, "testfile.txt"))
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle([file_name | _rest], context) do
    target = DomePath.expand(file_name, context.current_dir)
    target_rel = DomePath.relative_to(target, context.sandbox_root)
    config = to_sandbox_config(context)

    case Sandbox.validate_path(target_rel, config) do
      {:ok, safe_path} ->
        case File.touch(safe_path) do
          :ok -> {:ok, ""}
          {:error, reason} -> {:error, "touch: #{file_name}: #{Errors.to_message(reason)}\n"}
        end

      {:error, :outside_sandbox} ->
        {:error, "touch: #{file_name}: No such file or directory\n"}
    end
  end

  def handle([], _context) do
    {:error, "touch: missing file operand\n"}
  end

  # Convert legacy context map to SandboxConfig struct
  # Use sandbox_root as default_cwd because path is pre-resolved relative to sandbox_root
  defp to_sandbox_config(%{sandbox_root: root}) do
    %SandboxConfig{allowed_paths: [root], home_path: root}
  end
end
