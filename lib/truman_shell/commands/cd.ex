defmodule TrumanShell.Commands.Cd do
  @moduledoc """
  Handler for the `cd` command - change working directory.

  Unlike most commands, `cd` returns an updated context because it changes
  the shell's working directory. Returns `{:ok, "", ctx: new_ctx}` on success,
  where `new_ctx` has the updated `current_path`.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.DomePath
  alias TrumanShell.Support.Sandbox

  @doc """
  Changes the current working directory within the sandbox.

  Returns `{:ok, "", ctx: new_ctx}` on success with updated current_path.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> {:ok, "", ctx: new_ctx} = TrumanShell.Commands.Cd.handle(["lib"], ctx)
      iex> String.ends_with?(new_ctx.current_path, "/lib")
      true

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> TrumanShell.Commands.Cd.handle(["nonexistent"], ctx)
      {:error, "bash: cd: nonexistent: No such file or directory\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result_with_ctx()
  @impl true
  # No args means go home
  def handle([], ctx), do: go_home(ctx)

  # Tilde expansion is now handled by Stages.Expander before we get here.
  # By the time cd receives args, ~ has already been expanded to home_path.
  def handle([path | _], ctx) do
    change_directory(path, ctx)
  end

  # Home is sandbox_config.home_path
  defp go_home(ctx) do
    new_ctx = %{ctx | current_path: ctx.sandbox_config.home_path}
    {:ok, "", ctx: new_ctx}
  end

  defp change_directory(path, ctx) do
    # Expand path relative to current_path, then validate
    absolute_path = DomePath.expand(path, ctx.current_path)

    with {:ok, safe_path} <- Sandbox.validate_path(absolute_path, ctx.sandbox_config),
         {:dir, true} <- {:dir, File.dir?(safe_path)} do
      # Return success with updated ctx
      new_ctx = %{ctx | current_path: safe_path}
      {:ok, "", ctx: new_ctx}
    else
      {:error, :outside_sandbox} ->
        # 404 principle: don't reveal anything about paths outside sandbox
        {:error, "bash: cd: #{path}: No such file or directory\n"}

      {:dir, false} ->
        # Path is inside sandbox but not a directory - check if it's a file
        if File.regular?(absolute_path) do
          {:error, "bash: cd: #{path}: Not a directory\n"}
        else
          {:error, "bash: cd: #{path}: No such file or directory\n"}
        end
    end
  end
end
