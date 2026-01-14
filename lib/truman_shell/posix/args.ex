defmodule TrumanShell.Posix.Args do
  @moduledoc """
  Shared argument parsing utilities for POSIX-style commands.
  """

  @doc """
  Parse an integer flag like `-n 5` from argument list.

  Returns `{:ok, integer, remaining_args}` on success.

  ## Examples

      iex> TrumanShell.Posix.Args.parse_int_flag(["-n", "5", "file.txt"], "-n")
      {:ok, 5, ["file.txt"]}

  """
  @spec parse_int_flag(list(String.t()), String.t()) ::
          {:ok, integer(), list(String.t())}
          | {:error, String.t()}
          | {:not_found, list(String.t())}
  def parse_int_flag([flag, value | rest], flag) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n, rest}
      _ -> {:error, "invalid integer: '#{value}'"}
    end
  end

  # Flag present but no value follows
  def parse_int_flag([flag], flag) do
    {:error, "option requires an argument: '#{flag}'"}
  end

  def parse_int_flag(args, _flag) do
    {:not_found, args}
  end

  @doc """
  Parse a string flag like `-name pattern` from argument list.

  Returns `{:ok, string_value, remaining_args}` on success.

  ## Examples

      iex> TrumanShell.Posix.Args.parse_string_flag(["-name", "*.ex", "."], "-name")
      {:ok, "*.ex", ["."]}

  """
  @spec parse_string_flag(list(String.t()), String.t()) ::
          {:ok, String.t(), list(String.t())}
          | {:error, String.t()}
          | {:not_found, list(String.t())}
  def parse_string_flag([flag, value | rest], flag) do
    {:ok, value, rest}
  end

  def parse_string_flag([flag], flag) do
    {:error, "option requires an argument: '#{flag}'"}
  end

  def parse_string_flag(args, _flag) do
    {:not_found, args}
  end
end
