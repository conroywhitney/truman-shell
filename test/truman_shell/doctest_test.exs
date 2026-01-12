defmodule TrumanShell.DoctestTest do
  use ExUnit.Case, async: true

  # Run doctests from all public modules
  doctest TrumanShell
  doctest TrumanShell.Command
  doctest TrumanShell.Executor
end
