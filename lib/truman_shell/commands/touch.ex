defmodule TrumanShell.Commands.Touch do
  @moduledoc """
  Handler for the `touch` command - create empty files or update timestamps.

  Returns `{:ok, ""}` on success (silent like bash touch).
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Sanitizer

  @doc """
  Creates an empty file or updates timestamp within the sandbox.

  ## Examples

      iex> sandbox = Path.join(System.tmp_dir!(), "touch_doctest_#{System.unique_integer([:positive])}")
      iex> File.mkdir_p!(sandbox)
      iex> context = %{sandbox_root: sandbox, current_dir: sandbox}
      iex> {:ok, ""} = TrumanShell.Commands.Touch.handle(["testfile.txt"], context)
      iex> File.exists?(Path.join(sandbox, "testfile.txt"))
      true

  """
  @impl true
  def handle([file_name | _rest], context) do
    target = Path.expand(file_name, context.current_dir)
    target_rel = Path.relative_to(target, context.sandbox_root)

    case Sanitizer.validate_path(target_rel, context.sandbox_root) do
      {:ok, safe_path} ->
        case File.touch(safe_path) do
          :ok -> {:ok, ""}
          {:error, _} -> {:error, "touch: #{file_name}: No such file or directory\n"}
        end

      {:error, :outside_sandbox} ->
        {:error, "touch: #{file_name}: No such file or directory\n"}
    end
  end

  def handle([], _context) do
    {:error, "touch: missing file operand\n"}
  end
end
