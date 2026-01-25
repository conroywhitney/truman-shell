defmodule TrumanShell.Support.Tilde do
  @moduledoc """
  Tilde expansion for TrumanShell.

  Expands `~` to the sandbox root directory, similar to how bash
  expands `~` to the user's home directory.
  """

  alias TrumanShell.DomePath

  @doc """
  Expands tilde (`~`) in a path to the sandbox root.

  ## Examples

      iex> TrumanShell.Support.Tilde.expand("~", "/sandbox")
      "/sandbox"

      iex> TrumanShell.Support.Tilde.expand("~/foo", "/sandbox")
      "/sandbox/foo"

      iex> TrumanShell.Support.Tilde.expand("~/", "/sandbox")
      "/sandbox"

      iex> TrumanShell.Support.Tilde.expand("~//lib", "/sandbox")
      "/sandbox/lib"

      iex> TrumanShell.Support.Tilde.expand("/absolute/path", "/sandbox")
      "/absolute/path"

      iex> TrumanShell.Support.Tilde.expand("relative", "/sandbox")
      "relative"

      iex> TrumanShell.Support.Tilde.expand("~user", "/sandbox")
      "~user"

  ## Notes

  - `~user` syntax is not supported (passes through unchanged)
  - Multiple leading slashes after `~` are collapsed (e.g., `~//foo` → `/sandbox/foo`)
  """
  @spec expand(String.t(), String.t()) :: String.t()
  def expand("~", sandbox_root), do: sandbox_root

  def expand("~/", sandbox_root), do: sandbox_root

  def expand("~/" <> rest, sandbox_root) do
    # Strip leading slashes to handle ~//lib -> sandbox_root/lib
    subpath = String.trim_leading(rest, "/")
    DomePath.join(sandbox_root, subpath)
  end

  # No tilde or ~user (not supported) → pass through unchanged
  def expand(path, _sandbox_root), do: path
end
