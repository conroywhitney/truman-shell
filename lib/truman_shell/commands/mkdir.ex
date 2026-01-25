defmodule TrumanShell.Commands.Mkdir do
  @moduledoc """
  Handler for the `mkdir` command - create directories.

  Returns `{:ok, ""}` on success (silent like bash mkdir).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.DomePath
  alias TrumanShell.Support.Sandbox

  @doc """
  Creates a new directory within the sandbox.

  ## Examples

      iex> sandbox = Path.join([File.cwd!(), "tmp", "mkdir_doctest_#{System.unique_integer([:positive])}"])
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> context = %{sandbox_root: sandbox, current_dir: sandbox}
      iex> {:ok, ""} = TrumanShell.Commands.Mkdir.handle(["testdir"], context)
      iex> File.dir?(Path.join(sandbox, "testdir"))
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(["-p", dir_name | _rest], context) do
    create_directory(dir_name, context, parents: true)
  end

  def handle([dir_name | _rest], context) do
    create_directory(dir_name, context, parents: false)
  end

  def handle([], _context) do
    {:error, "mkdir: missing operand\n"}
  end

  defp create_directory(dir_name, context, parents: true) do
    target = DomePath.expand(dir_name, context.current_dir)
    target_rel = DomePath.relative_to(target, context.sandbox_root)
    config = to_sandbox_config(context)

    case Sandbox.validate_path(target_rel, config) do
      {:ok, safe_path} ->
        # mkdir -p never fails for existing directories
        File.mkdir_p(safe_path)
        {:ok, ""}

      {:error, :outside_sandbox} ->
        {:error, "mkdir: #{dir_name}: No such file or directory\n"}
    end
  end

  defp create_directory(dir_name, context, parents: false) do
    target = DomePath.expand(dir_name, context.current_dir)
    target_rel = DomePath.relative_to(target, context.sandbox_root)
    config = to_sandbox_config(context)

    case Sandbox.validate_path(target_rel, config) do
      {:ok, safe_path} ->
        case File.mkdir(safe_path) do
          :ok -> {:ok, ""}
          {:error, :eexist} -> {:error, "mkdir: #{dir_name}: File exists\n"}
          {:error, _} -> {:error, "mkdir: #{dir_name}: No such file or directory\n"}
        end

      {:error, :outside_sandbox} ->
        {:error, "mkdir: #{dir_name}: No such file or directory\n"}
    end
  end

  # Convert legacy context map to SandboxConfig struct
  # Use sandbox_root as default_cwd because path is pre-resolved relative to sandbox_root
  defp to_sandbox_config(%{sandbox_root: root}) do
    %SandboxConfig{roots: [root], default_cwd: root}
  end
end
