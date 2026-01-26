defmodule TrumanShell.Commands.Rm do
  @moduledoc """
  Handler for the `rm` command - SOFT DELETE files to .trash.

  **CRITICAL**: This command NEVER actually deletes files!
  Instead, it moves them to `.trash/{unique_id}_{filename}` for auditability.

  This is the key difference from real bash - in Truman Shell,
  all operations are reversible for debugging and safety.

  ## TODO: Trash Cleanup (v0.5+)

  Currently `.trash/` is unbounded. Consider implementing:
  - Max item count (e.g., keep last 1000 files)
  - Age-based cleanup (e.g., delete after 24 hours)
  - Size quota (e.g., max 100MB trash)
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.DomePath
  alias TrumanShell.Support.Sandbox

  @doc """
  Soft deletes a file by moving it to .trash within the sandbox.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> sandbox = Path.join([File.cwd!(), "tmp", "rm_doctest_#{System.unique_integer([:positive])}"])
      iex> File.rm_rf(sandbox)
      iex> File.mkdir_p!(sandbox)
      iex> File.mkdir_p!(Path.join(sandbox, ".trash"))
      iex> File.write!(Path.join(sandbox, "test.txt"), "content")
      iex> config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      iex> ctx = %Context{current_path: sandbox, sandbox_config: config}
      iex> {:ok, ""} = TrumanShell.Commands.Rm.handle(["test.txt"], ctx)
      iex> File.exists?(Path.join(sandbox, "test.txt"))
      false

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(["-f" | rest], ctx) do
    # -f flag: don't error on missing files
    handle_rm(rest, ctx, force: true)
  end

  def handle(["-r" | rest], ctx) do
    # -r flag: recursive (for directories)
    handle_rm(rest, ctx, recursive: true)
  end

  def handle(["-rf" | rest], ctx) do
    handle_rm(rest, ctx, force: true, recursive: true)
  end

  def handle(["-fr" | rest], ctx) do
    handle_rm(rest, ctx, force: true, recursive: true)
  end

  def handle([file_name | _rest], ctx) do
    handle_rm([file_name], ctx, [])
  end

  def handle([], _ctx) do
    {:error, "rm: missing operand\n"}
  end

  defp handle_rm([file_name | _], ctx, opts) do
    case Sandbox.validate_path(file_name, ctx) do
      {:ok, safe_path} ->
        soft_delete(safe_path, file_name, ctx.sandbox_config.home_path, opts)

      {:error, :outside_sandbox} ->
        {:error, "rm: #{file_name}: No such file or directory\n"}
    end
  end

  defp handle_rm([], _ctx, _opts) do
    {:error, "rm: missing operand\n"}
  end

  defp soft_delete(safe_path, file_name, sandbox_root, opts) do
    cond do
      File.regular?(safe_path) ->
        move_to_trash(safe_path, file_name, sandbox_root)

      File.dir?(safe_path) && opts[:recursive] ->
        move_to_trash(safe_path, file_name, sandbox_root)

      File.dir?(safe_path) ->
        {:error, "rm: #{file_name}: is a directory\n"}

      opts[:force] ->
        {:ok, ""}

      true ->
        {:error, "rm: #{file_name}: No such file or directory\n"}
    end
  end

  defp move_to_trash(safe_path, file_name, sandbox_root) do
    trash_dir = DomePath.join(sandbox_root, ".trash")
    # Ensure .trash exists
    File.mkdir_p(trash_dir)

    # Generate unique-prefixed name to avoid collisions
    # System.unique_integer guarantees uniqueness even for rapid successive calls
    unique_id = System.unique_integer([:positive, :monotonic])
    basename = DomePath.basename(file_name)
    trash_name = "#{unique_id}_#{basename}"
    trash_path = DomePath.join(trash_dir, trash_name)

    case File.rename(safe_path, trash_path) do
      :ok -> {:ok, ""}
      {:error, _} -> {:error, "rm: #{file_name}: No such file or directory\n"}
    end
  end
end
