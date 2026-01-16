defmodule TrumanShell.Commands.Date do
  @moduledoc """
  Handler for the `date` command - print current date and time.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @doc """
  Returns the current date and time in Unix format.

  Uses space-padded day to match Unix `date` output (e.g., "Jan  9" not "Jan 09").

  ## Examples

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> {:ok, output} = TrumanShell.Commands.Date.handle([], context)
      iex> output =~ ~r/^\\w{3} \\w{3} [ \\d]\\d \\d{2}:\\d{2}:\\d{2} \\w+ \\d{4}\\n$/
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, _context) do
    now = DateTime.now!("Etc/UTC")
    {:ok, format_date(now) <> "\n"}
  end

  # Format: "Thu Jan  9 10:30:45 UTC 2026"
  # Note: Elixir's Calendar.strftime doesn't support %e (space-padded day),
  # so we use strftime for most fields and handle day padding manually.
  defp format_date(dt) do
    # Space-pad day to 2 chars (Unix style: " 9" not "09")
    day = String.pad_leading("#{dt.day}", 2, " ")

    Calendar.strftime(dt, "%a %b ") <> day <> Calendar.strftime(dt, " %H:%M:%S %Z %Y")
  end
end
