defmodule TrumanShell.Commands.Cd do
  @moduledoc """
  Handler for the `cd` command - change working directory.

  Returns `{:ok, "", set_cwd: path}` on success, which the executor
  uses to update the current working directory state.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Sanitizer

  @doc """
  Changes the current working directory within the sandbox.

  Returns `{:ok, "", set_cwd: new_path}` on success. The executor
  applies the `set_cwd` side effect to update state.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, "", set_cwd: new_dir} = TrumanShell.Commands.Cd.handle(["lib"], context)
      iex> String.ends_with?(new_dir, "/lib")
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Cd.handle(["nonexistent"], context)
      {:error, "bash: cd: nonexistent: No such file or directory\\n"}

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Cd.handle(["/etc"], context)
      {:error, "bash: cd: /etc: No such file or directory\\n"}

  """
  @impl true
  def handle(args, context) do
    path = List.first(args) || "."
    change_directory(path, context)
  end

  defp change_directory(path, context) do
    # Compute target path relative to current working directory
    # Then make it relative to sandbox for validation
    target_abs = Path.expand(path, context.current_dir)
    target_rel = Path.relative_to(target_abs, context.sandbox_root)

    with {:ok, safe_path} <- Sanitizer.validate_path(target_rel, context.sandbox_root),
         true <- File.dir?(safe_path) do
      # Return success with the new cwd for executor to apply
      {:ok, "", set_cwd: safe_path}
    else
      {:error, :outside_sandbox} ->
        {:error, "bash: cd: #{path}: No such file or directory\n"}

      false ->
        {:error, "bash: cd: #{path}: No such file or directory\n"}

      {:error, _} ->
        {:error, "bash: cd: #{path}: No such file or directory\n"}
    end
  end
end
