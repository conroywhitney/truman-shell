defmodule TrumanShell.DoctestTest do
  use ExUnit.Case, async: true

  # Run doctests from all public modules
  doctest TrumanShell
  doctest TrumanShell.Command
  doctest TrumanShell.Executor

  # Command handlers
  doctest TrumanShell.Commands.Pwd
  doctest TrumanShell.Commands.Ls
  doctest TrumanShell.Commands.Cd
  doctest TrumanShell.Commands.Cat
  doctest TrumanShell.Commands.Head
  doctest TrumanShell.Commands.Tail
end
