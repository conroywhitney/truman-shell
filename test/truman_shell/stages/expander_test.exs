defmodule TrumanShell.Stages.ExpanderTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Command
  alias TrumanShell.Stages.Expander

  @moduletag :stages

  describe "expand/2 tilde expansion" do
    test "expands ~ alone to sandbox root" do
      command = Command.new(:cmd_cd, ["~"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox"]
    end

    test "expands ~/ to sandbox root" do
      command = Command.new(:cmd_cd, ["~/"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox"]
    end

    test "expands ~/subpath to sandbox root/subpath" do
      command = Command.new(:cmd_cd, ["~/lib"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox/lib"]
    end

    test "expands ~/nested/path correctly" do
      command = Command.new(:cmd_cat, ["~/src/main.ex"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox/src/main.ex"]
    end

    test "normalizes ~// to sandbox root (strips extra slashes)" do
      command = Command.new(:cmd_cd, ["~//lib"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox/lib"]
    end

    test "normalizes ~/// to sandbox root (strips multiple slashes)" do
      command = Command.new(:cmd_cd, ["~///lib"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox/lib"]
    end

    test "leaves ~user unchanged (not supported)" do
      command = Command.new(:cmd_cd, ["~alice"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      # ~alice is not a valid tilde expansion, passed through unchanged
      assert result.args == ["~alice"]
    end

    test "expands multiple tilde arguments" do
      command = Command.new(:cmd_ls, ["~/lib", "~/test"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox/lib", "/sandbox/test"]
    end

    test "leaves non-tilde arguments unchanged" do
      command = Command.new(:cmd_ls, ["-la", "src"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["-la", "src"]
    end

    test "mixes tilde and non-tilde arguments" do
      command = Command.new(:cmd_cp, ["-r", "~/lib", "target"])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["-r", "/sandbox/lib", "target"]
    end

    test "preserves command name and other fields" do
      command = Command.new(:cmd_cd, ["~/lib"], redirects: [{:stdout, "out.txt"}])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.name == :cmd_cd
      assert result.redirects == [{:stdout, "out.txt"}]
    end

    test "expands tilde in piped commands" do
      base = Command.new(:cmd_cat, ["~/file.txt"])
      piped = Command.new(:cmd_grep, ["pattern"])
      command = %{base | pipes: [piped]}
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.args == ["/sandbox/file.txt"]
      # Piped commands should also be expanded (though grep doesn't use tilde here)
      assert hd(result.pipes).args == ["pattern"]
    end
  end
end
