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

    # TODO: Revisit - should absolute paths be confined or rejected?
    # Current: /etc/passwd -> sandbox/etc/passwd (confined)
    # Alternative: /etc/passwd -> :error (rejected)
    # See: GPT review feedback on Path.safe_relative/2
    rel_path = Path.relative(path)

    case Path.safe_relative(rel_path, sandbox_expanded) do
      {:ok, safe_rel} ->
        {:ok, Path.expand(safe_rel, sandbox_expanded)}

      :error ->
        {:error, :outside_sandbox}
    end
  end
end
