defmodule TrumanShell.Commands.Mv do
  @moduledoc """
  Handler for the `mv` command - move/rename files.

  Returns `{:ok, ""}` on success (silent like bash mv).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Posix.Errors
  alias TrumanShell.Support.Sandbox

  @doc """
  Moves or renames a file within the sandbox.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> sandbox = Path.join([File.cwd!(), "tmp", "mv_doctest_#{System.unique_integer([:positive])}"])
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> File.write!(Path.join(sandbox, "src.txt"), "content")
      iex> config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      iex> ctx = %Context{current_path: sandbox, sandbox_config: config}
      iex> {:ok, ""} = TrumanShell.Commands.Mv.handle(["src.txt", "dst.txt"], ctx)
      iex> File.exists?(Path.join(sandbox, "dst.txt"))
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle([src, dst | _rest], ctx) do
    with {:ok, src_safe} <- Sandbox.validate_path(src, ctx),
         {:ok, dst_safe} <- Sandbox.validate_path(dst, ctx),
         true <- File.exists?(src_safe) do
      case File.rename(src_safe, dst_safe) do
        :ok -> {:ok, ""}
        {:error, reason} -> {:error, "mv: #{src}: #{Errors.to_message(reason)}\n"}
      end
    else
      {:error, :outside_sandbox} ->
        {:error, "mv: #{src}: No such file or directory\n"}

      false ->
        {:error, "mv: #{src}: No such file or directory\n"}
    end
  end

  def handle([_single], _ctx) do
    {:error, "mv: missing destination file operand\n"}
  end

  def handle([], _ctx) do
    {:error, "mv: missing file operand\n"}
  end
end
