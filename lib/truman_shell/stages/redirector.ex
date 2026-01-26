defmodule TrumanShell.Stages.Redirector do
  @moduledoc """
  Handles stdout redirection to files as a pipeline stage.

  Runs after Executor, applying any redirects in the Command struct.
  Validates paths against sandbox boundaries (404 principle).

  ## Redirect Types

  - `:stdout` - Write redirect (`>`) - creates/overwrites file
  - `:stdout_append` - Append redirect (`>>`) - appends to file

  ## Bash Behavior

  For multiple redirects (`echo hello > a.txt > b.txt`):
  - Only the LAST redirect receives the output
  - Earlier redirects create/truncate the file with empty content
  """

  alias TrumanShell.Commands.Context
  alias TrumanShell.Posix.Errors
  alias TrumanShell.Support.Sandbox

  @doc """
  Apply redirects to command output.

  Returns `{:ok, remaining_output}` on success or `{:error, message}` on failure.
  For redirects that consume output, `remaining_output` is empty string.
  For no redirects, the original output is passed through unchanged.

  ## Context

  Requires a `%Commands.Context{}` struct with:
  - `:current_path` - Current working directory for relative paths
  - `:sandbox_config` - Sandbox configuration for validation
  """
  @spec apply(String.t(), [{atom(), String.t()}], Context.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def apply(output, redirects, ctx) do
    do_apply(output, redirects, ctx)
  end

  # No redirects - pass output through unchanged
  defp do_apply(output, [], _ctx), do: {:ok, output}

  # Write redirect (>)
  defp do_apply(output, [{:stdout, path} | rest], ctx) do
    write_redirect(output, path, [], rest, ctx)
  end

  # Append redirect (>>)
  defp do_apply(output, [{:stdout_append, path} | rest], ctx) do
    write_redirect(output, path, [:append], rest, ctx)
  end

  # Skip unsupported redirect types (stdin, stderr)
  defp do_apply(output, [_unsupported | rest], ctx) do
    do_apply(output, rest, ctx)
  end

  defp write_redirect(output, path, write_opts, rest, ctx) do
    # Bash behavior: for multiple redirects, only LAST one gets output
    # Earlier redirects are truncated/created with empty content
    {content_to_write, next_output} =
      if rest == [] do
        {output, ""}
      else
        {"", output}
      end

    with {:ok, safe_path} <- Sandbox.validate_path(path, ctx),
         :ok <- do_write_file(safe_path, content_to_write, write_opts, path) do
      do_apply(next_output, rest, ctx)
    else
      {:error, :outside_sandbox} ->
        {:error, "bash: #{path}: No such file or directory\n"}

      {:error, _} = error ->
        error
    end
  end

  # Wrap File.write to return bash-like errors instead of crashing
  defp do_write_file(safe_path, content, write_opts, original_path) do
    case File.write(safe_path, content, write_opts) do
      :ok -> :ok
      {:error, reason} -> {:error, "bash: #{original_path}: #{Errors.to_message(reason)}\n"}
    end
  end
end
