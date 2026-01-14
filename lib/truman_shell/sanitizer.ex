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

  Uses Elixir's `Path.safe_relative/2` which protects against:
  - Directory traversal attacks (../)
  - Symlinks that point outside the sandbox
  """
  @spec validate_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, :outside_sandbox}
  def validate_path(path, sandbox_root) do
    sandbox_expanded = Path.expand(sandbox_root)

    # Reject absolute paths outside sandbox (AIITL transparency principle)
    # Instead of silently confining /etc -> sandbox/etc, we reject entirely.
    # This is more honest - the AI learns sandbox boundaries explicitly.
    #
    # SECURITY: Must check directory boundary, not just string prefix!
    # "/tmp/sandbox2" must NOT pass for sandbox "/tmp/sandbox"
    if String.starts_with?(path, "/") and not path_within_sandbox?(path, sandbox_expanded) do
      {:error, :outside_sandbox}
    else
      # For relative paths (or absolute within sandbox), validate normally
      rel_path = Path.relative_to(path, sandbox_expanded)

      case Path.safe_relative(rel_path, sandbox_expanded) do
        {:ok, safe_rel} ->
          {:ok, Path.expand(safe_rel, sandbox_expanded)}

        :error ->
          {:error, :outside_sandbox}
      end
    end
  end

  # Check if path is within sandbox using proper directory boundary check.
  # "/tmp/sandbox/file" is within "/tmp/sandbox"
  # "/tmp/sandbox2/file" is NOT within "/tmp/sandbox" (different directory!)
  defp path_within_sandbox?(path, sandbox) do
    path == sandbox or String.starts_with?(path, sandbox <> "/")
  end
end
