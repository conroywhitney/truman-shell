defmodule TrumanShell.DoctestTest do
  use ExUnit.Case, async: true

  # Run doctests from all public modules
  doctest TrumanShell
  doctest TrumanShell.Command
  doctest TrumanShell.Executor

  # Shared utilities
  doctest TrumanShell.Support.FileIO
  doctest TrumanShell.Support.TreeWalker

  # Command handlers
  doctest TrumanShell.Commands.Pwd
  doctest TrumanShell.Commands.Ls
  doctest TrumanShell.Commands.Cd
  doctest TrumanShell.Commands.Cat
  doctest TrumanShell.Commands.Head
  doctest TrumanShell.Commands.Tail
  doctest TrumanShell.Commands.Echo
  doctest TrumanShell.Commands.Find
  doctest TrumanShell.Commands.Grep
  doctest TrumanShell.Commands.Mkdir
  doctest TrumanShell.Commands.Touch
  doctest TrumanShell.Commands.Rm
  doctest TrumanShell.Commands.Mv
  doctest TrumanShell.Commands.Cp
  doctest TrumanShell.Commands.Wc
end
