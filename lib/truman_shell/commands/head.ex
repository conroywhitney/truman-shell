defmodule TrumanShell.Commands.Head do
  @moduledoc """
  Handler for the `head` command - display first n lines of a file.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Helpers

  @impl true
  def handle(args, context) do
    {n, path} = parse_args(args)

    case Helpers.read_file(path, context) do
      {:ok, contents} ->
        lines = String.split(contents, "\n")
        result = lines |> Enum.take(n) |> Enum.join("\n")
        {:ok, if(result == "", do: "", else: result <> "\n")}

      {:error, msg} ->
        {:error, Helpers.format_error("head", msg)}
    end
  end

  # Parse head arguments: -n NUM or -NUM or just file
  defp parse_args(["-n", n_str | rest]) do
    n = String.to_integer(n_str)
    path = List.first(rest) || "-"
    {n, path}
  end

  defp parse_args(["-" <> n_str | rest]) when n_str != "" do
    n = String.to_integer(n_str)
    path = List.first(rest) || "-"
    {n, path}
  end

  defp parse_args([path]) do
    {10, path}
  end

  defp parse_args([]) do
    {10, "-"}
  end
end
