defmodule TrumanShell.Commands.Mv do
  @moduledoc """
  Handler for the `mv` command - move/rename files.

  Returns `{:ok, ""}` on success (silent like bash mv).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Posix.Errors
  alias TrumanShell.Sanitizer

  @doc """
  Moves or renames a file within the sandbox.

  ## Examples

      iex> sandbox = Path.join(System.tmp_dir!(), "mv_doctest_#{System.unique_integer([:positive])}")
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> File.write!(Path.join(sandbox, "src.txt"), "content")
      iex> context = %{sandbox_root: sandbox, current_dir: sandbox}
      iex> {:ok, ""} = TrumanShell.Commands.Mv.handle(["src.txt", "dst.txt"], context)
      iex> File.exists?(Path.join(sandbox, "dst.txt"))
      true

  """
  @impl true
  def handle([src, dst | _rest], context) do
    src_target = Path.expand(src, context.current_dir)
    src_rel = Path.relative_to(src_target, context.sandbox_root)

    dst_target = Path.expand(dst, context.current_dir)
    dst_rel = Path.relative_to(dst_target, context.sandbox_root)

    with {:ok, src_safe} <- Sanitizer.validate_path(src_rel, context.sandbox_root),
         {:ok, dst_safe} <- Sanitizer.validate_path(dst_rel, context.sandbox_root),
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

  def handle([_single], _context) do
    {:error, "mv: missing destination file operand\n"}
  end

  def handle([], _context) do
    {:error, "mv: missing file operand\n"}
  end
end
