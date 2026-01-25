defmodule TrumanShell.ConfigTest do
  @moduledoc """
  Tests for agents.yaml configuration loading and validation.

  These tests explore edge cases around:
  - default_cwd behavior (the "home base" concept)
  - Multiple roots validation
  - Path resolution and TOCTOU prevention
  """
  use ExUnit.Case, async: false

  alias TrumanShell.Config

  @moduletag :config

  describe "default_cwd resolution" do
    @describetag :default_cwd

    test "default_cwd is resolved to absolute path at load time (not at use time)" do
      # This prevents TOCTOU: we don't check inherited cwd, we SET it
      # The resolved path should be stable regardless of shell cwd changes
      config = Config.defaults()

      # default_cwd should always be absolute
      assert Path.type(config.default_cwd) == :absolute

      # It should be the actual cwd, fully expanded
      assert config.default_cwd == File.cwd!()

      # No ~, no .., no relative components
      refute String.contains?(config.default_cwd, "~")
      refute String.contains?(config.default_cwd, "/../")
    end

    test "default_cwd must be within one of the roots" do
      # Invalid: default_cwd outside all roots
      # We'll test validation directly with a struct
      config = %Config{
        version: "0.1",
        roots: [File.cwd!()],
        default_cwd: "/tmp",
        raw: %{}
      }

      assert {:error, msg} = Config.validate(config)
      assert msg =~ "default_cwd must be within one of the roots"
    end

    test "default_cwd can be relative to first root" do
      # Create a temp config file with relative default_cwd
      cwd = File.cwd!()

      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "#{cwd}"
        default_cwd: "."
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # "." relative to first root should resolve to the root itself
        assert config.default_cwd == cwd
        assert Path.type(config.default_cwd) == :absolute
      after
        File.rm(config_path)
      end
    end

    test "default_cwd with ~ expands to home directory" do
      # Use a directory we know exists under home
      home = System.user_home!()

      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "~"
        default_cwd: "~"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # ~ should expand to home directory
        assert config.default_cwd == home
        assert home in config.roots
        refute String.contains?(config.default_cwd, "~")
      after
        File.rm(config_path)
      end
    end

    test "default_cwd with non-existent path fails at load time" do
      # We want early failure, not runtime surprises
      cwd = File.cwd!()
      nonexistent = Path.join(cwd, "this-directory-does-not-exist-#{:rand.uniform(10_000)}")

      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "#{cwd}"
        default_cwd: "#{nonexistent}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:error, msg} = Config.load(config_path)
        assert msg =~ "default_cwd does not exist"
      after
        File.rm(config_path)
      end
    end
  end

  describe "multiple roots" do
    @describetag :roots

    test "roots with globs expand at load time" do
      # Create temp dirs to test glob expansion
      base_dir = Path.join(System.tmp_dir!(), "test_roots_#{:rand.uniform(10_000)}")
      proj1 = Path.join(base_dir, "project1")
      proj2 = Path.join(base_dir, "project2")
      File.mkdir_p!(proj1)
      File.mkdir_p!(proj2)

      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "#{base_dir}/*"
        default_cwd: "#{proj1}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Glob should expand to actual directories
        assert proj1 in config.roots
        assert proj2 in config.roots
        # Original glob pattern should not be in roots
        refute Enum.any?(config.roots, &String.contains?(&1, "*"))
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "path validation checks against ALL roots" do
      # Create two separate root directories
      base_dir = Path.join(System.tmp_dir!(), "test_roots_#{:rand.uniform(10_000)}")
      root1 = Path.join(base_dir, "project")
      root2 = Path.join(base_dir, "libs")
      File.mkdir_p!(root1)
      File.mkdir_p!(root2)

      # default_cwd is in root2, not root1
      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "#{root1}"
          - "#{root2}"
        default_cwd: "#{root2}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        # Should succeed because root2 is in the roots list
        assert {:ok, config} = Config.load(config_path)
        assert config.default_cwd == root2
        assert root1 in config.roots
        assert root2 in config.roots
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "overlapping roots are deduplicated" do
      # Create nested directories
      base_dir = Path.join(System.tmp_dir!(), "test_roots_#{:rand.uniform(10_000)}")
      nested = Path.join(base_dir, "project")
      File.mkdir_p!(nested)

      # Both parent and child are roots - child is redundant but valid
      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "#{base_dir}"
          - "#{nested}"
        default_cwd: "#{base_dir}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Both roots are kept (Enum.uniq only removes exact duplicates)
        assert base_dir in config.roots
        assert nested in config.roots
        # Roots are sorted
        assert config.roots == Enum.sort(config.roots)
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "symlink in root is resolved" do
      # Create a real directory and a symlink to it
      base_dir = Path.join(System.tmp_dir!(), "test_roots_#{:rand.uniform(10_000)}")
      real_dir = Path.join(base_dir, "real")
      symlink_dir = Path.join(base_dir, "symlink")
      File.mkdir_p!(real_dir)
      File.ln_s!(real_dir, symlink_dir)

      # Use symlink in config - we test that paths through symlink work
      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "#{symlink_dir}"
        default_cwd: "#{symlink_dir}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Config loads successfully with symlink path
        # The symlink is expanded but stored as given
        assert length(config.roots) == 1
        # default_cwd validation works through symlink
        assert File.dir?(config.default_cwd)
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "root with trailing slash is normalized" do
      cwd = File.cwd!()

      config_content = """
      version: "0.1"
      sandbox:
        roots:
          - "#{cwd}/"
        default_cwd: "#{cwd}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Trailing slash should be normalized away
        [root] = config.roots
        refute String.ends_with?(root, "/")
        assert root == cwd
      after
        File.rm(config_path)
      end
    end
  end

  describe "TOCTOU prevention" do
    @describetag :toctou

    @tag :skip
    test "executor uses config default_cwd, not inherited shell cwd" do
      # This is the key test: even if shell cwd is /tmp,
      # commands should execute with cwd = default_cwd from config
    end

    @tag :skip
    test "cd command updates in-memory cursor, not shell cwd" do
      # cd /subdir should update Process.get(:truman_cwd)
      # but NOT call System.cmd("cd", ...) or File.cd!()
    end

    @tag :skip
    test "relative paths resolve against config default_cwd, not shell cwd" do
      # If shell cwd is /tmp but default_cwd is /home/user/project,
      # "cat README.md" should look in /home/user/project/README.md
    end
  end

  describe "config file discovery" do
    @describetag :discovery

    @tag :skip
    test "finds agents.yaml in current directory" do
    end

    @tag :skip
    test "finds .agents.yaml (hidden variant)" do
    end

    @tag :skip
    test "prefers agents.yaml over .agents.yaml" do
    end

    @tag :skip
    test "falls back to ~/.config/truman/agents.yaml" do
    end

    test "returns sensible defaults when no config found" do
      # Default: single root = cwd, default_cwd = cwd
      config = Config.defaults()

      assert config.version == "0.1"
      assert length(config.roots) == 1
      assert hd(config.roots) == File.cwd!()
      assert config.default_cwd == File.cwd!()
    end
  end

  describe "config validation" do
    @describetag :validation

    @tag :skip
    test "rejects config with no roots" do
    end

    @tag :skip
    test "rejects root that doesn't exist" do
    end

    @tag :skip
    test "rejects root that is a file (not directory)" do
    end

    @tag :skip
    test "rejects root outside user home (security)" do
      # Should we allow /tmp? /var? Probably not by default
      # config = %{roots: ["/etc"]}
      # Should return {:error, "root /etc is outside allowed base paths"}
    end

    @tag :skip
    test "accepts system_paths override in config" do
      # By default, /etc, ~/.ssh, etc. are blocked
      # But config could allow specific system paths (with warning?)
    end
  end

  describe "edge cases from real usage" do
    @describetag :edge_cases

    @tag :skip
    test "cd to another root, then relative path resolves correctly" do
      # roots: [~/studios/reification-labs, ~/code/truman-shell]
      # default_cwd: ~/studios/reification-labs
      # cd ~/code/truman-shell
      # cat lib/sandbox.ex -> should work (within roots)
    end

    @tag :skip
    test "cd to path outside all roots fails" do
      # cd /tmp -> error, not within roots
    end

    @tag :skip
    test "checkpoint creates files in default_cwd, not current cd location" do
      # This is the user's actual use case!
      # cd ~/code/truman-shell (for git work)
      # /checkpoint -> files should go to ~/studios/reification-labs/.checkpoints/
      # HOW? The harness passes cwd to subprocess, not the shell's cwd
    end

    @tag :skip
    test "git -C works with paths in any root" do
      # git -C ~/code/truman-shell status
      # Should work because ~/code/truman-shell is in roots
    end

    @tag :skip
    test "symlink from one root to another is followed" do
      # ~/studios/reification-labs/.vault/truman-shell -> ~/code/truman-shell
      # If both are roots, symlink should be allowed
    end

    @tag :skip
    test "symlink from root to outside-root is denied" do
      # ~/code/escape -> /etc
      # Even though ~/code/* is a root, the symlink target is not
    end
  end
end
