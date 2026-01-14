defmodule TrumanShell.PosixErrors do
  @moduledoc """
  Shared POSIX error to bash-like message conversion.

  Used by commands and executor for consistent error messages.
  """

  @doc """
  Convert POSIX error atoms to bash-like error messages.

  ## Examples

      iex> TrumanShell.PosixErrors.to_message(:enoent)
      "No such file or directory"

      iex> TrumanShell.PosixErrors.to_message(:eisdir)
      "Is a directory"

  """
  @spec to_message(atom()) :: String.t()
  def to_message(:enoent), do: "No such file or directory"
  def to_message(:eisdir), do: "Is a directory"
  def to_message(:enotdir), do: "Not a directory"
  def to_message(:eacces), do: "Permission denied"
  def to_message(:enospc), do: "No space left on device"
  def to_message(:erofs), do: "Read-only file system"
  def to_message(:eexist), do: "File exists"
  def to_message(:exdev), do: "Invalid cross-device link"
  def to_message(reason), do: "#{reason}"
end
