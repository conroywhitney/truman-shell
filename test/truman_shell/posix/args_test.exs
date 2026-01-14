defmodule TrumanShell.Posix.ArgsTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Posix.Args

  describe "parse_int_flag/2" do
    test "parses -n 5 style flag and returns remaining args" do
      args = ["-n", "5", "file.txt"]
      assert {:ok, 5, ["file.txt"]} = Args.parse_int_flag(args, "-n")
    end

    test "returns error for non-integer value" do
      args = ["-n", "foo", "file.txt"]
      assert {:error, "invalid integer: 'foo'"} = Args.parse_int_flag(args, "-n")
    end

    test "returns error for partial integer like '5abc'" do
      # Integer.parse("5abc") returns {5, "abc"} - we reject partial matches
      args = ["-n", "5abc", "file.txt"]
      assert {:error, "invalid integer: '5abc'"} = Args.parse_int_flag(args, "-n")
    end

    test "returns :not_found when flag is not present" do
      # Allows caller to use a default value
      args = ["file.txt"]
      assert {:not_found, ["file.txt"]} = Args.parse_int_flag(args, "-n")
    end

    test "returns error when flag is present but value is missing" do
      # Like `head -n` with no number - bash says "option requires an argument"
      args = ["-n"]
      assert {:error, "option requires an argument: '-n'"} = Args.parse_int_flag(args, "-n")
    end
  end

  describe "parse_string_flag/2" do
    test "parses -name pattern style flag and returns remaining args" do
      args = ["-name", "*.ex", "."]
      assert {:ok, "*.ex", ["."]} = Args.parse_string_flag(args, "-name")
    end

    test "returns :not_found when flag is not present" do
      args = ["."]
      assert {:not_found, ["."]} = Args.parse_string_flag(args, "-name")
    end

    test "returns error when flag is present but value is missing" do
      args = ["-name"]
      assert {:error, "option requires an argument: '-name'"} = Args.parse_string_flag(args, "-name")
    end
  end
end
