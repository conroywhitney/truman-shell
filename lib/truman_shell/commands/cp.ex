defmodule TrumanShell.Commands.Cp do
  @moduledoc """
  Handler for the `cp` command - copy files.

  Returns `{:ok, ""}` on success (silent like bash cp).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Commands.Context
  alias TrumanShell.DomePath
  alias TrumanShell.Posix.Errors
  alias TrumanShell.Support.Sandbox

  @doc """
  Copies a file within the sandbox.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> sandbox = Path.join([File.cwd!(), "tmp", "cp_doctest_#{System.unique_integer([:positive])}"])
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> File.write!(Path.join(sandbox, "src.txt"), "content")
      iex> config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      iex> ctx = %Context{current_path: sandbox, sandbox_config: config}
      iex> {:ok, ""} = TrumanShell.Commands.Cp.handle(["src.txt", "dst.txt"], ctx)
      iex> File.exists?(Path.join(sandbox, "dst.txt"))
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(["-r", src, dst | _rest], ctx) do
    copy_file(src, dst, ctx, recursive: true)
  end

  def handle([src, dst | _rest], ctx) do
    copy_file(src, dst, ctx, [])
  end

  def handle([_single], _ctx) do
    {:error, "cp: missing destination file operand\n"}
  end

  def handle([], _ctx) do
    {:error, "cp: missing file operand\n"}
  end

  defp copy_file(src, dst, %Context{} = ctx, opts) do
    src_target = DomePath.expand(src, ctx.current_path)
    src_rel = DomePath.relative_to(src_target, ctx.sandbox_config.home_path)

    dst_target = DomePath.expand(dst, ctx.current_path)
    dst_rel = DomePath.relative_to(dst_target, ctx.sandbox_config.home_path)

    with {:ok, src_safe} <- Sandbox.validate_path(src_rel, ctx.sandbox_config),
         {:ok, dst_safe} <- Sandbox.validate_path(dst_rel, ctx.sandbox_config) do
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
