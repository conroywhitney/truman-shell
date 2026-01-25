defmodule TrumanShell.Stages.ExpanderTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Command
  alias TrumanShell.Commands.Context
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.Stages.Expander

  @moduletag :stages

  # Helper to build ctx
  defp build_ctx(sandbox_root, opts \\ []) do
    current_path = Keyword.get(opts, :current_path, sandbox_root)
    config = %SandboxConfig{allowed_paths: [sandbox_root], home_path: sandbox_root}
    %Context{current_path: current_path, sandbox_config: config}
  end

  describe "expand/2 tilde expansion" do
    test "expands ~ alone to sandbox root" do
      command = Command.new(:cmd_cd, ["~"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox"]
    end

    test "expands ~/ to sandbox root" do
      command = Command.new(:cmd_cd, ["~/"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox"]
    end

    test "expands ~/subpath to sandbox root/subpath" do
      command = Command.new(:cmd_cd, ["~/lib"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox/lib"]
    end

    test "expands ~/nested/path correctly" do
      command = Command.new(:cmd_cat, ["~/src/main.ex"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox/src/main.ex"]
    end

    test "normalizes ~// to sandbox root (strips extra slashes)" do
      command = Command.new(:cmd_cd, ["~//lib"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox/lib"]
    end

    test "normalizes ~/// to sandbox root (strips multiple slashes)" do
      command = Command.new(:cmd_cd, ["~///lib"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox/lib"]
    end

    test "leaves ~user unchanged (not supported)" do
      command = Command.new(:cmd_cd, ["~alice"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      # ~alice is not a valid tilde expansion, passed through unchanged
      assert result.args == ["~alice"]
    end

    test "expands multiple tilde arguments" do
      command = Command.new(:cmd_ls, ["~/lib", "~/test"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox/lib", "/sandbox/test"]
    end

    test "leaves non-tilde arguments unchanged" do
      command = Command.new(:cmd_ls, ["-la", "src"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["-la", "src"]
    end

    test "mixes tilde and non-tilde arguments" do
      command = Command.new(:cmd_cp, ["-r", "~/lib", "target"])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["-r", "/sandbox/lib", "target"]
    end

    test "preserves command name and other fields" do
      command = Command.new(:cmd_cd, ["~/lib"], redirects: [{:stdout, "out.txt"}])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.name == :cmd_cd
      assert result.redirects == [{:stdout, "out.txt"}]
    end

    test "expands tilde in piped commands" do
      base = Command.new(:cmd_cat, ["~/file.txt"])
      piped = Command.new(:cmd_grep, ["pattern"])
      command = %{base | pipes: [piped]}
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.args == ["/sandbox/file.txt"]
      # Piped commands should also be expanded (though grep doesn't use tilde here)
      assert hd(result.pipes).args == ["pattern"]
    end
  end

  describe "expand/2 redirect tilde expansion" do
    test "expands ~ in stdout redirect target" do
      command = Command.new(:cmd_echo, ["hello"], redirects: [{:stdout, "~/out.txt"}])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.redirects == [{:stdout, "/sandbox/out.txt"}]
    end

    test "expands ~ in stdout_append redirect target" do
      command = Command.new(:cmd_echo, ["more"], redirects: [{:stdout_append, "~/log.txt"}])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.redirects == [{:stdout_append, "/sandbox/log.txt"}]
    end

    test "expands ~/subpath in redirect target" do
      command = Command.new(:cmd_echo, ["data"], redirects: [{:stdout, "~/logs/app.log"}])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

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

      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.redirects == [
               {:stdout, "/sandbox/out.txt"},
               {:stderr, "/sandbox/err.txt"}
             ]
    end

    test "leaves non-tilde redirect paths unchanged" do
      command = Command.new(:cmd_echo, ["hi"], redirects: [{:stdout, "out.txt"}])
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert result.redirects == [{:stdout, "out.txt"}]
    end

    test "expands tilde in piped command redirects" do
      base = Command.new(:cmd_echo, ["hello"])
      piped = Command.new(:cmd_grep, ["hello"], redirects: [{:stdout, "~/filtered.txt"}])
      command = %{base | pipes: [piped]}
      ctx = build_ctx("/sandbox")

      result = Expander.expand(command, ctx)

      assert hd(result.pipes).redirects == [{:stdout, "/sandbox/filtered.txt"}]
    end
  end

  describe "expand/2 glob expansion" do
    setup do
      # Create a unique temp directory for filesystem tests
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "expander_glob_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, sandbox_root: tmp_dir}
    end

    test "expands {:glob, *.md} to matching files", %{sandbox_root: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "README.md"), "readme")
      File.write!(Path.join(sandbox, "CHANGELOG.md"), "changelog")

      # Use {:glob, pattern} tuple to mark as expandable (matches Parser output)
      command = Command.new(:cmd_ls, [{:glob, "*.md"}])
      ctx = build_ctx(sandbox)

      result = Expander.expand(command, ctx)

      assert result.args == ["CHANGELOG.md", "README.md"]
    end

    test "expands tilde then glob ~/*.md", %{sandbox_root: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "README.md"), "readme")
      File.write!(Path.join(sandbox, "CHANGELOG.md"), "changelog")

      command = Command.new(:cmd_ls, [{:glob, "~/*.md"}])
      ctx = build_ctx(sandbox)

      result = Expander.expand(command, ctx)

      # Tilde expands to sandbox, then glob finds files
      assert result.args == ["#{sandbox}/CHANGELOG.md", "#{sandbox}/README.md"]
    end

    test "preserves non-glob args", %{sandbox_root: sandbox} do
      command = Command.new(:cmd_ls, ["-la", "src"])
      ctx = build_ctx(sandbox)

      result = Expander.expand(command, ctx)

      assert result.args == ["-la", "src"]
    end

    test "mixes glob and non-glob args", %{sandbox_root: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "a.md"), "a")
      File.write!(Path.join(sandbox, "b.md"), "b")

      # -n is literal string, *.md is {:glob, ...} - matches Parser output
      command = Command.new(:cmd_cat, ["-n", {:glob, "*.md"}])
      ctx = build_ctx(sandbox)

      result = Expander.expand(command, ctx)

      assert result.args == ["-n", "a.md", "b.md"]
    end

    test "no-match glob returns original pattern", %{sandbox_root: sandbox} do
      command = Command.new(:cmd_ls, [{:glob, "*.nonexistent"}])
      ctx = build_ctx(sandbox)

      result = Expander.expand(command, ctx)

      assert result.args == ["*.nonexistent"]
    end

    test "expands glob in piped commands", %{sandbox_root: sandbox} do
      # Create test files
      File.write!(Path.join(sandbox, "a.txt"), "content-a")
      File.write!(Path.join(sandbox, "b.txt"), "content-b")

      # cat *.txt | grep pattern
      base = Command.new(:cmd_cat, [{:glob, "*.txt"}])
      piped = Command.new(:cmd_grep, ["pattern"])
      command = %{base | pipes: [piped]}
      ctx = build_ctx(sandbox)

      result = Expander.expand(command, ctx)

      # Base command args should be expanded
      assert result.args == ["a.txt", "b.txt"]
      # Piped command args should be unchanged (no glob)
      assert hd(result.pipes).args == ["pattern"]
    end
  end

  describe "expand/2 with Context struct" do
    setup do
      # Create a unique temp directory for filesystem tests
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "expander_ctx_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, sandbox_root: tmp_dir, subdir: subdir}
    end

    test "glob expands relative to current_path, not home_path", %{sandbox_root: sandbox, subdir: subdir} do
      # Create files in subdir only
      File.write!(Path.join(subdir, "found.txt"), "in subdir")

      # Create file in sandbox root (should NOT match since we're in subdir)
      File.write!(Path.join(sandbox, "root.txt"), "at root")

      # Simulate: cd subdir && ls *.txt
      # current_path = subdir (where we cd'd to)
      # home_path = sandbox (static, for ~ expansion)
      ctx = build_ctx(sandbox, current_path: subdir)

      command = Command.new(:cmd_ls, [{:glob, "*.txt"}])
      result = Expander.expand(command, ctx)

      # Should find subdir/found.txt, NOT sandbox/root.txt
      assert result.args == ["found.txt"]
    end

    test "tilde still expands to home_path when current_path differs", %{sandbox_root: sandbox, subdir: subdir} do
      # Create file at sandbox root
      File.write!(Path.join(sandbox, "home.txt"), "at home")

      # Simulate: cd subdir && cat ~/home.txt
      ctx = build_ctx(sandbox, current_path: subdir)

      command = Command.new(:cmd_cat, ["~/home.txt"])
      result = Expander.expand(command, ctx)

      # Tilde should expand to home_path (sandbox), not current_path (subdir)
      assert result.args == ["#{sandbox}/home.txt"]
    end
  end
end
