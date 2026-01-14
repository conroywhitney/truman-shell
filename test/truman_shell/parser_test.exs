defmodule TrumanShell.ParserTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Command
  alias TrumanShell.Parser

  # ==========================================================================
  # TDD Fixtures from reification-labs/.imaginary/research/2026-01-11_shell-tdd-fixtures.csv
  # Phase: v0.3 (Basic) - pwd, cd, unknown commands
  # ==========================================================================

  describe "pwd - Print Working Directory (v0.3)" do
    test "basic pwd" do
      assert {:ok, %Command{name: :cmd_pwd, args: []}} = Parser.parse("pwd")
    end

    test "pwd with -L flag" do
      assert {:ok, %Command{name: :cmd_pwd, args: ["-L"]}} = Parser.parse("pwd -L")
    end

    test "pwd with -P flag" do
      assert {:ok, %Command{name: :cmd_pwd, args: ["-P"]}} = Parser.parse("pwd -P")
    end
  end

  describe "cd - Change Directory (v0.3)" do
    test "change to absolute path" do
      assert {:ok, %Command{name: :cmd_cd, args: ["/tmp"]}} = Parser.parse("cd /tmp")
    end

    test "change to home with tilde" do
      assert {:ok, %Command{name: :cmd_cd, args: ["~"]}} = Parser.parse("cd ~")
    end

    test "change to parent" do
      assert {:ok, %Command{name: :cmd_cd, args: [".."]}} = Parser.parse("cd ..")
    end

    test "change to relative path" do
      assert {:ok, %Command{name: :cmd_cd, args: ["./subdir"]}} = Parser.parse("cd ./subdir")
    end

    test "change to home (no args)" do
      assert {:ok, %Command{name: :cmd_cd, args: []}} = Parser.parse("cd")
    end

    test "nonexistent path parses correctly" do
      # Parser doesn't validate paths - that's for the executor
      assert {:ok, %Command{name: :cmd_cd, args: ["/nonexistent/path"]}} =
               Parser.parse("cd /nonexistent/path")
    end

    test "file path parses correctly" do
      # Parser doesn't validate if path is a file vs directory
      assert {:ok, %Command{name: :cmd_cd, args: ["/etc/passwd"]}} =
               Parser.parse("cd /etc/passwd")
    end

    test "cd with dash flag (previous directory)" do
      assert {:ok, %Command{name: :cmd_cd, args: ["-"]}} = Parser.parse("cd -")
    end
  end

  describe "unknown commands (v0.3)" do
    test "unknown command returns {:unknown, name} tuple (prevents atom DoS)" do
      assert {:ok, %Command{name: {:unknown, "nonexistent_cmd"}, args: []}} =
               Parser.parse("nonexistent_cmd")
    end

    test "kubectl is unknown (not in allowlist)" do
      assert {:ok, %Command{name: {:unknown, "kubectl"}, args: ["get", "pods"]}} =
               Parser.parse("kubectl get pods")
    end

    test "docker is unknown (not in allowlist)" do
      assert {:ok, %Command{name: {:unknown, "docker"}, args: ["ps"]}} =
               Parser.parse("docker ps")
    end

    test "Command.known?/1 returns false for unknown commands" do
      {:ok, cmd} = Parser.parse("kubectl get pods")
      refute Command.known?(cmd)
    end

    test "Command.known?/1 returns true for known commands" do
      {:ok, cmd} = Parser.parse("ls -la")
      assert Command.known?(cmd)
    end
  end

  # ==========================================================================
  # Phase: v0.4 (Read Operations) - ls, cat, head, tail
  # ==========================================================================

  describe "ls - List Directory (v0.4)" do
    test "basic ls" do
      assert {:ok, %Command{name: :cmd_ls, args: []}} = Parser.parse("ls")
    end

    test "ls with -l flag" do
      assert {:ok, %Command{name: :cmd_ls, args: ["-l"]}} = Parser.parse("ls -l")
    end

    test "ls with -la flags" do
      assert {:ok, %Command{name: :cmd_ls, args: ["-la"]}} = Parser.parse("ls -la")
    end

    test "ls with path" do
      assert {:ok, %Command{name: :cmd_ls, args: ["-la", "/tmp"]}} = Parser.parse("ls -la /tmp")
    end

    test "ls with glob pattern" do
      assert {:ok, %Command{name: :cmd_ls, args: ["*.md"]}} = Parser.parse("ls *.md")
    end
  end

  describe "cat - Read Files (v0.4)" do
    test "basic cat" do
      assert {:ok, %Command{name: :cmd_cat, args: ["file.txt"]}} = Parser.parse("cat file.txt")
    end

    test "cat with path" do
      assert {:ok, %Command{name: :cmd_cat, args: ["/etc/hosts"]}} =
               Parser.parse("cat /etc/hosts")
    end

    test "cat multiple files" do
      assert {:ok, %Command{name: :cmd_cat, args: ["file1.txt", "file2.txt"]}} =
               Parser.parse("cat file1.txt file2.txt")
    end

    test "cat with -n flag" do
      assert {:ok, %Command{name: :cmd_cat, args: ["-n", "file.txt"]}} =
               Parser.parse("cat -n file.txt")
    end
  end

  describe "head - First N Lines (v0.4)" do
    test "basic head" do
      assert {:ok, %Command{name: :cmd_head, args: ["file.txt"]}} = Parser.parse("head file.txt")
    end

    test "head with number flag" do
      assert {:ok, %Command{name: :cmd_head, args: ["-5", "file.txt"]}} =
               Parser.parse("head -5 file.txt")
    end

    test "head with -n flag" do
      assert {:ok, %Command{name: :cmd_head, args: ["-n", "3", "file.txt"]}} =
               Parser.parse("head -n 3 file.txt")
    end
  end

  describe "tail - Last N Lines (v0.4)" do
    test "basic tail" do
      assert {:ok, %Command{name: :cmd_tail, args: ["file.txt"]}} = Parser.parse("tail file.txt")
    end

    test "tail with number flag" do
      assert {:ok, %Command{name: :cmd_tail, args: ["-5", "file.txt"]}} =
               Parser.parse("tail -5 file.txt")
    end
  end

  # ==========================================================================
  # Phase: v0.5 (Search Operations) - grep, find, wc
  # ==========================================================================

  describe "grep - Search Content (v0.5)" do
    test "basic grep" do
      assert {:ok, %Command{name: :cmd_grep, args: ["pattern", "file.txt"]}} =
               Parser.parse("grep pattern file.txt")
    end

    test "grep with -n flag" do
      assert {:ok, %Command{name: :cmd_grep, args: ["-n", "pattern", "file.txt"]}} =
               Parser.parse("grep -n pattern file.txt")
    end

    test "grep with -r flag" do
      assert {:ok, %Command{name: :cmd_grep, args: ["-r", "pattern", "."]}} =
               Parser.parse("grep -r pattern .")
    end

    test "grep with multiple flags" do
      assert {:ok, %Command{name: :cmd_grep, args: ["-A", "2", "pattern", "file.txt"]}} =
               Parser.parse("grep -A 2 pattern file.txt")
    end
  end

  describe "find - Locate Files (v0.5)" do
    test "find by name" do
      assert {:ok, %Command{name: :cmd_find, args: [".", "-name", "*.txt"]}} =
               Parser.parse("find . -name \"*.txt\"")
    end

    test "find by type" do
      assert {:ok, %Command{name: :cmd_find, args: [".", "-type", "f"]}} =
               Parser.parse("find . -type f")
    end
  end

  describe "wc - Word Count (v0.5)" do
    test "basic wc" do
      assert {:ok, %Command{name: :cmd_wc, args: ["file.txt"]}} = Parser.parse("wc file.txt")
    end

    test "wc with -l flag" do
      assert {:ok, %Command{name: :cmd_wc, args: ["-l", "file.txt"]}} =
               Parser.parse("wc -l file.txt")
    end
  end

  # ==========================================================================
  # Phase: v0.6 (Write Operations) - mkdir, touch, rm, mv, cp, echo, date
  # ==========================================================================

  describe "mkdir - Create Directory (v0.6)" do
    test "basic mkdir" do
      assert {:ok, %Command{name: :cmd_mkdir, args: ["newdir"]}} = Parser.parse("mkdir newdir")
    end

    test "mkdir with -p flag" do
      assert {:ok, %Command{name: :cmd_mkdir, args: ["-p", "path/to/nested"]}} =
               Parser.parse("mkdir -p path/to/nested")
    end
  end

  describe "echo - Output Text (v0.6)" do
    test "basic echo" do
      assert {:ok, %Command{name: :cmd_echo, args: ["hello"]}} = Parser.parse("echo hello")
    end

    test "echo with quoted string" do
      assert {:ok, %Command{name: :cmd_echo, args: ["hello world"]}} =
               Parser.parse("echo \"hello world\"")
    end

    test "echo with -n flag" do
      assert {:ok, %Command{name: :cmd_echo, args: ["-n", "hello"]}} =
               Parser.parse("echo -n hello")
    end
  end

  describe "rm - Remove Files (v0.6)" do
    test "basic rm" do
      assert {:ok, %Command{name: :cmd_rm, args: ["file.txt"]}} = Parser.parse("rm file.txt")
    end

    test "rm with -r flag" do
      assert {:ok, %Command{name: :cmd_rm, args: ["-r", "directory"]}} =
               Parser.parse("rm -r directory")
    end

    test "rm with -rf flags" do
      assert {:ok, %Command{name: :cmd_rm, args: ["-rf", "directory"]}} =
               Parser.parse("rm -rf directory")
    end
  end

  describe "additional write commands (v0.6)" do
    test "touch parses correctly" do
      assert {:ok, %Command{name: :cmd_touch, args: ["newfile.txt"]}} =
               Parser.parse("touch newfile.txt")
    end

    test "mv parses correctly" do
      assert {:ok, %Command{name: :cmd_mv, args: ["old.txt", "new.txt"]}} =
               Parser.parse("mv old.txt new.txt")
    end

    test "cp parses correctly" do
      assert {:ok, %Command{name: :cmd_cp, args: ["-r", "src", "dest"]}} =
               Parser.parse("cp -r src dest")
    end

    test "date parses correctly" do
      assert {:ok, %Command{name: :cmd_date, args: ["+%Y-%m-%d"]}} =
               Parser.parse("date +%Y-%m-%d")
    end
  end

  describe "utility commands" do
    test "which parses correctly" do
      assert {:ok, %Command{name: :cmd_which, args: ["ls"]}} = Parser.parse("which ls")
    end

    test "type parses correctly" do
      assert {:ok, %Command{name: :cmd_type, args: ["cd"]}} = Parser.parse("type cd")
    end

    test "true parses correctly" do
      assert {:ok, %Command{name: :cmd_true, args: []}} = Parser.parse("true")
    end

    test "false parses correctly" do
      assert {:ok, %Command{name: :cmd_false, args: []}} = Parser.parse("false")
    end
  end

  # ==========================================================================
  # Phase: v0.7 (Composition) - pipes, redirects, chains
  # ==========================================================================

  describe "pipes (v0.7)" do
    test "cat to head" do
      assert {:ok,
              %Command{
                name: :cmd_cat,
                args: ["file.txt"],
                pipes: [%Command{name: :cmd_head, args: ["-5"]}]
              }} =
               Parser.parse("cat file.txt | head -5")
    end

    test "cat to grep" do
      assert {:ok,
              %Command{
                name: :cmd_cat,
                args: ["file.txt"],
                pipes: [%Command{name: :cmd_grep, args: ["pattern"]}]
              }} =
               Parser.parse("cat file.txt | grep pattern")
    end

    test "cat to wc" do
      assert {:ok,
              %Command{
                name: :cmd_cat,
                args: ["file.txt"],
                pipes: [%Command{name: :cmd_wc, args: ["-l"]}]
              }} =
               Parser.parse("cat file.txt | wc -l")
    end

    test "triple pipe" do
      {:ok, cmd} = Parser.parse("cat file.txt | grep pattern | head -3")

      assert cmd.name == :cmd_cat
      assert cmd.args == ["file.txt"]
      assert length(cmd.pipes) == 2

      [grep_cmd, head_cmd] = cmd.pipes
      assert grep_cmd.name == :cmd_grep
      assert grep_cmd.args == ["pattern"]
      assert head_cmd.name == :cmd_head
      assert head_cmd.args == ["-3"]
    end
  end

  describe "redirects (v0.7)" do
    test "stdout redirect" do
      {:ok, cmd} = Parser.parse("echo hello > file.txt")

      assert cmd.name == :cmd_echo
      assert cmd.args == ["hello"]
      assert cmd.redirects == [{:stdout, "file.txt"}]
    end

    test "stdout append" do
      {:ok, cmd} = Parser.parse("echo more >> file.txt")

      assert cmd.name == :cmd_echo
      assert cmd.args == ["more"]
      assert cmd.redirects == [{:stdout_append, "file.txt"}]
    end

    test "stderr redirect" do
      {:ok, cmd} = Parser.parse("ls /nonexistent 2> error.log")

      assert cmd.name == :cmd_ls
      assert cmd.args == ["/nonexistent"]
      assert cmd.redirects == [{:stderr, "error.log"}]
    end

    test "malformed redirect without target is skipped (lenient parsing)" do
      # Parser is lenient: redirect without target is skipped rather than error
      # This matches bash behavior where "echo hello >" at a prompt waits for more input
      {:ok, cmd} = Parser.parse("echo hello >")

      assert cmd.name == :cmd_echo
      assert cmd.args == ["hello"]
      assert cmd.redirects == []
    end

    test "malformed stderr redirect without target is skipped" do
      {:ok, cmd} = Parser.parse("cat file.txt 2>")

      assert cmd.name == :cmd_cat
      assert cmd.args == ["file.txt"]
      assert cmd.redirects == []
    end
  end

  # ==========================================================================
  # Edge Cases
  # ==========================================================================

  describe "edge cases" do
    test "empty string returns error" do
      assert {:error, "Empty command"} = Parser.parse("")
    end

    test "whitespace only returns error" do
      assert {:error, "Empty command"} = Parser.parse("   ")
    end

    test "quoted strings with spaces" do
      assert {:ok, %Command{name: :cmd_ls, args: ["file with spaces.txt"]}} =
               Parser.parse("ls \"file with spaces.txt\"")
    end

    test "single quoted strings" do
      assert {:ok, %Command{name: :cmd_echo, args: ["hello world"]}} =
               Parser.parse("echo 'hello world'")
    end

    test "tilde expansion in path" do
      assert {:ok, %Command{name: :cmd_ls, args: ["~/Documents"]}} =
               Parser.parse("ls ~/Documents")
    end

    test "parent relative path" do
      assert {:ok, %Command{name: :cmd_ls, args: ["../sibling"]}} =
               Parser.parse("ls ../sibling")
    end
  end
end
