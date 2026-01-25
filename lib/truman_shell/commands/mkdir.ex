defmodule TrumanShell.Commands.Mkdir do
  @moduledoc """
  Handler for the `mkdir` command - create directories.

  Returns `{:ok, ""}` on success (silent like bash mkdir).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Commands.Context
  alias TrumanShell.DomePath
  alias TrumanShell.Support.Sandbox

  @doc """
  Creates a new directory within the sandbox.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> sandbox = Path.join([File.cwd!(), "tmp", "mkdir_doctest_#{System.unique_integer([:positive])}"])
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      iex> ctx = %Context{current_path: sandbox, sandbox_config: config}
      iex> {:ok, ""} = TrumanShell.Commands.Mkdir.handle(["testdir"], ctx)
      iex> File.dir?(Path.join(sandbox, "testdir"))
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(["-p", dir_name | _rest], ctx) do
    create_directory(dir_name, ctx, parents: true)
  end

  def handle([dir_name | _rest], ctx) do
    create_directory(dir_name, ctx, parents: false)
  end

  def handle([], _ctx) do
    {:error, "mkdir: missing operand\n"}
  end

  defp create_directory(dir_name, %Context{} = ctx, parents: true) do
    target = DomePath.expand(dir_name, ctx.current_path)
    target_rel = DomePath.relative_to(target, ctx.sandbox_config.home_path)

    case Sandbox.validate_path(target_rel, ctx.sandbox_config) do
      {:ok, safe_path} ->
        # mkdir -p never fails for existing directories
        File.mkdir_p(safe_path)
        {:ok, ""}

      {:error, :outside_sandbox} ->
        {:error, "mkdir: #{dir_name}: No such file or directory\n"}
    end
  end

  defp create_directory(dir_name, %Context{} = ctx, parents: false) do
    target = DomePath.expand(dir_name, ctx.current_path)
    target_rel = DomePath.relative_to(target, ctx.sandbox_config.home_path)

    case Sandbox.validate_path(target_rel, ctx.sandbox_config) do
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
end
