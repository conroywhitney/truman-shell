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

  describe "expand/2 redirect tilde expansion" do
    test "expands ~ in stdout redirect target" do
      command = Command.new(:cmd_echo, ["hello"], redirects: [{:stdout, "~/out.txt"}])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.redirects == [{:stdout, "/sandbox/out.txt"}]
    end

    test "expands ~ in stdout_append redirect target" do
      command = Command.new(:cmd_echo, ["more"], redirects: [{:stdout_append, "~/log.txt"}])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.redirects == [{:stdout_append, "/sandbox/log.txt"}]
    end

    test "expands ~/subpath in redirect target" do
      command = Command.new(:cmd_echo, ["data"], redirects: [{:stdout, "~/logs/app.log"}])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.redirects == [{:stdout, "/sandbox/logs/app.log"}]
    end

    test "expands tilde in multiple redirects" do
      command =
        Command.new(:cmd_echo, ["hi"],
          redirects: [
            {:stdout, "~/out.txt"},
            {:stderr, "~/err.txt"}
          ]
        )

      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.redirects == [
               {:stdout, "/sandbox/out.txt"},
               {:stderr, "/sandbox/err.txt"}
             ]
    end

    test "leaves non-tilde redirect paths unchanged" do
      command = Command.new(:cmd_echo, ["hi"], redirects: [{:stdout, "out.txt"}])
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert result.redirects == [{:stdout, "out.txt"}]
    end

    test "expands tilde in piped command redirects" do
      base = Command.new(:cmd_echo, ["hello"])
      piped = Command.new(:cmd_grep, ["hello"], redirects: [{:stdout, "~/filtered.txt"}])
      command = %{base | pipes: [piped]}
      context = %{sandbox_root: "/sandbox"}

      result = Expander.expand(command, context)

      assert hd(result.pipes).redirects == [{:stdout, "/sandbox/filtered.txt"}]
    end
  end
end
