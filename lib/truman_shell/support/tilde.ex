defmodule TrumanShell.Support.Tilde do
  @moduledoc """
  Tilde expansion for TrumanShell.

  Expands `~` to the agent's home directory (sandbox home_path),
  similar to how bash expands `~` to the user's home directory.
  """

  alias TrumanShell.DomePath

  @doc """
  Expands tilde (`~`) in a path to the home directory.

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
  - Multiple leading slashes after `~` are collapsed (e.g., `~//foo` → `/home/foo`)
  """
  @spec expand(String.t(), String.t()) :: String.t()
  def expand("~", home_path), do: home_path

  def expand("~/", home_path), do: home_path

  def expand("~/" <> rest, home_path) do
    # Strip leading slashes to handle ~//lib -> home_path/lib
    subpath = String.trim_leading(rest, "/")
    DomePath.join(home_path, subpath)
  end

  # No tilde or ~user (not supported) → pass through unchanged
  def expand(path, _home_path), do: path
end
