defmodule TrumanShell.Commands.Cd do
  @moduledoc """
  Handler for the `cd` command - change working directory.

  Returns `{:ok, "", set_cwd: path}` on success, which the executor
  uses to update the current working directory state.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Sanitizer

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
