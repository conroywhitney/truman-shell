defmodule TrumanShell.Commands.Cp do
  @moduledoc """
  Handler for the `cp` command - copy files.

  Returns `{:ok, ""}` on success (silent like bash cp).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.DomePath
  alias TrumanShell.Posix.Errors
  alias TrumanShell.Support.Sandbox

  @doc """
  Copies a file within the sandbox.

  ## Examples

      iex> sandbox = Path.join(System.tmp_dir!(), "cp_doctest_#{System.unique_integer([:positive])}")
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> File.write!(Path.join(sandbox, "src.txt"), "content")
      iex> context = %{sandbox_root: sandbox, current_dir: sandbox}
      iex> {:ok, ""} = TrumanShell.Commands.Cp.handle(["src.txt", "dst.txt"], context)
      iex> File.exists?(Path.join(sandbox, "dst.txt"))
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(["-r", src, dst | _rest], context) do
    copy_file(src, dst, context, recursive: true)
  end

  def handle([src, dst | _rest], context) do
    copy_file(src, dst, context, [])
  end

  def handle([_single], _context) do
    {:error, "cp: missing destination file operand\n"}
  end

  def handle([], _context) do
    {:error, "cp: missing file operand\n"}
  end

  defp copy_file(src, dst, context, opts) do
    src_target = DomePath.expand(src, context.current_dir)
    src_rel = DomePath.relative_to(src_target, context.sandbox_root)

    dst_target = DomePath.expand(dst, context.current_dir)
    dst_rel = DomePath.relative_to(dst_target, context.sandbox_root)

    with {:ok, src_safe} <- Sandbox.validate_path(src_rel, context.sandbox_root),
         {:ok, dst_safe} <- Sandbox.validate_path(dst_rel, context.sandbox_root) do
      do_copy(src_safe, dst_safe, src, opts)
    else
      {:error, :outside_sandbox} ->
        {:error, "cp: #{src}: No such file or directory\n"}
    end
  end

  defp do_copy(src_safe, dst_safe, src_name, opts) do
    cond do
      File.regular?(src_safe) ->
        copy_regular_file(src_safe, dst_safe, src_name)

      File.dir?(src_safe) ->
        copy_directory(src_safe, dst_safe, src_name, opts)

      true ->
        {:error, "cp: #{src_name}: No such file or directory\n"}
    end
  end

  defp copy_regular_file(src_safe, dst_safe, src_name) do
    case File.copy(src_safe, dst_safe) do
      {:ok, _} -> {:ok, ""}
      {:error, reason} -> {:error, "cp: #{src_name}: #{Errors.to_message(reason)}\n"}
    end
  end

  defp copy_directory(src_safe, dst_safe, src_name, opts) do
    if opts[:recursive] do
      case File.cp_r(src_safe, dst_safe) do
        {:ok, _} -> {:ok, ""}
        {:error, reason, _file} -> {:error, "cp: #{src_name}: #{Errors.to_message(reason)}\n"}
      end
    else
      {:error, "cp: -r not specified; omitting directory '#{src_name}'\n"}
    end
  end
end
