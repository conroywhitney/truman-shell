defmodule TrumanShell.Commands.Echo do
  @moduledoc """
  Handler for the `echo` command.

  Outputs arguments separated by spaces, followed by a newline.
  Supports `-n` flag to omit trailing newline.

  ## Examples

      iex> TrumanShell.Commands.Echo.handle(["hello"], %{})
      {:ok, "hello\\n"}

      iex> TrumanShell.Commands.Echo.handle(["hello", "world"], %{})
      {:ok, "hello world\\n"}

      iex> TrumanShell.Commands.Echo.handle([], %{})
      {:ok, "\\n"}

      iex> TrumanShell.Commands.Echo.handle(["-n", "hello"], %{})
      {:ok, "hello"}

  """

  @behaviour TrumanShell.Commands.Behaviour

  @impl true
  def handle(["-n" | rest], _context) do
    output = Enum.join(rest, " ")
    {:ok, output}
  end

  def handle(args, _context) do
    output = Enum.join(args, " ") <> "\n"
    {:ok, output}
  end
end
