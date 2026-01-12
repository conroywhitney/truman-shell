defmodule TrumanShell.Sanitizer do
  @moduledoc """
  Path sanitization and validation for the Truman Shell sandbox.

  Implements the "404 Principle" - paths outside the sandbox appear
  as "not found" rather than "permission denied" to avoid information leakage.
  """

  @doc """
  Validates that a path resolves within the sandbox root.

  Returns `{:ok, resolved_path}` if the path is safe,
  or `{:error, :outside_sandbox}` if it would escape.
  """
  @spec validate_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, :outside_sandbox}
  def validate_path(path, sandbox_root) do
    sandbox_expanded = Path.expand(sandbox_root)
    resolved = Path.join(sandbox_root, path) |> Path.expand()

    if String.starts_with?(resolved, sandbox_expanded <> "/") or resolved == sandbox_expanded do
      {:ok, resolved}
    else
      {:error, :outside_sandbox}
    end
  end
end
