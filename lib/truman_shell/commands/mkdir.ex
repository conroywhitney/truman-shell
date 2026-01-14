defmodule TrumanShell.Commands.Mkdir do
  @moduledoc """
  Handler for the `mkdir` command - create directories.

  Returns `{:ok, ""}` on success (silent like bash mkdir).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Sanitizer

  @doc """
  Creates a new directory within the sandbox.

  ## Examples

      iex> sandbox = Path.join(System.tmp_dir!(), "mkdir_doctest_#{:rand.uniform(100_000)}")
      iex> File.mkdir_p!(sandbox)
      iex> context = %{sandbox_root: sandbox, current_dir: sandbox}
      iex> {:ok, ""} = TrumanShell.Commands.Mkdir.handle(["testdir"], context)
      iex> File.dir?(Path.join(sandbox, "testdir"))
      true

  """
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
    target = Path.expand(dir_name, context.current_dir)
    target_rel = Path.relative_to(target, context.sandbox_root)

    case Sanitizer.validate_path(target_rel, context.sandbox_root) do
      {:ok, safe_path} ->
        # mkdir -p never fails for existing directories
        File.mkdir_p(safe_path)
        {:ok, ""}

      {:error, :outside_sandbox} ->
        {:error, "mkdir: #{dir_name}: No such file or directory\n"}
    end
  end

  defp create_directory(dir_name, context, parents: false) do
    target = Path.expand(dir_name, context.current_dir)
    target_rel = Path.relative_to(target, context.sandbox_root)

    case Sanitizer.validate_path(target_rel, context.sandbox_root) do
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
