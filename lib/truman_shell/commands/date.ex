defmodule TrumanShell.Commands.Date do
  @moduledoc """
  Handler for the `date` command - print current date and time.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @days ~w(Mon Tue Wed Thu Fri Sat Sun)
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc """
  Returns the current date and time in Unix format.

  ## Examples

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> {:ok, output} = TrumanShell.Commands.Date.handle([], context)
      iex> output =~ ~r/^\\w{3} \\w{3} \\d{1,2} \\d{2}:\\d{2}:\\d{2} \\w+ \\d{4}\\n$/
      true

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, _context) do
    now = DateTime.now!("Etc/UTC")
    {:ok, format_date(now) <> "\n"}
  end

  defp format_date(dt) do
    day_name = Enum.at(@days, Date.day_of_week(dt) - 1)
    month_name = Enum.at(@months, dt.month - 1)
    day = dt.day
    hour = String.pad_leading("#{dt.hour}", 2, "0")
    minute = String.pad_leading("#{dt.minute}", 2, "0")
    second = String.pad_leading("#{dt.second}", 2, "0")
    year = dt.year

    "#{day_name} #{month_name} #{day} #{hour}:#{minute}:#{second} UTC #{year}"
  end
end
