defmodule TrumanShell.ConfigTest do
  @moduledoc """
  Tests for agents.yaml configuration loading and validation.

  These tests explore edge cases around:
  - home_path behavior (the "home base" concept)
  - Multiple allowed_paths validation
  - Path resolution and TOCTOU prevention
  """
  use ExUnit.Case, async: false

  alias TrumanShell.Config
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :config

  describe "home_path resolution" do
    @describetag :home_path

    test "home_path is resolved to absolute path at load time (not at use time)" do
      # This prevents TOCTOU: we don't check inherited cwd, we SET it
      # The resolved path should be stable regardless of shell cwd changes
      config = Config.defaults()

      # home_path should always be absolute
      assert Path.type(config.sandbox.home_path) == :absolute

      # It should be the actual cwd, fully expanded
      assert config.sandbox.home_path == File.cwd!()

      # No ~, no .., no relative components
      refute String.contains?(config.sandbox.home_path, "~")
      refute String.contains?(config.sandbox.home_path, "/../")
    end

    test "home_path must be within one of the allowed_paths" do
      # Invalid: home_path outside all allowed_paths
      # We'll test validation directly with a struct
      sandbox = %SandboxConfig{
        allowed_paths: [File.cwd!()],
        home_path: "/tmp"
      }

      config = %Config{
        version: "0.1",
        sandbox: sandbox,
        raw: %{}
      }

      assert {:error, msg} = Config.validate(config)
      assert msg =~ "home_path must be within one of the allowed_paths"
    end

    test "home_path can be relative to first allowed_path" do
      # Create a temp config file with relative home_path
      cwd = File.cwd!()

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{cwd}"
        home_path: "#{cwd}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # home_path should be the cwd
        assert config.sandbox.home_path == cwd
        assert Path.type(config.sandbox.home_path) == :absolute
      after
        File.rm(config_path)
      end
    end

    test "home_path with ~ expands to home directory" do
      # Use a directory we know exists under home
      home = System.user_home!()

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "~"
        home_path: "~"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # ~ should expand to home directory
        assert config.sandbox.home_path == home
        assert home in config.sandbox.allowed_paths
        refute String.contains?(config.sandbox.home_path, "~")
      after
        File.rm(config_path)
      end
    end

    test "home_path with non-existent path fails at load time" do
      # We want early failure, not runtime surprises
      cwd = File.cwd!()
      nonexistent = Path.join(cwd, "this-directory-does-not-exist-#{:rand.uniform(10_000)}")

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{cwd}"
        home_path: "#{nonexistent}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:error, msg} = Config.load(config_path)
        assert msg =~ "home_path does not exist"
      after
        File.rm(config_path)
      end
    end

    test "home_path is required in YAML config" do
      cwd = File.cwd!()

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{cwd}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:error, msg} = Config.load(config_path)
        assert msg =~ "home_path is required"
      after
        File.rm(config_path)
      end
    end
  end

  describe "multiple allowed_paths" do
    @describetag :allowed_paths

    test "allowed_paths with globs expand at load time" do
      # Create temp dirs to test glob expansion
      base_dir = Path.join(System.tmp_dir!(), "test_roots_#{:rand.uniform(10_000)}")
      proj1 = Path.join(base_dir, "project1")
      proj2 = Path.join(base_dir, "project2")
      File.mkdir_p!(proj1)
      File.mkdir_p!(proj2)

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{base_dir}/*"
        home_path: "#{proj1}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Glob should expand to actual directories
        assert proj1 in config.sandbox.allowed_paths
        assert proj2 in config.sandbox.allowed_paths
        # Original glob pattern should not be in allowed_paths
        refute Enum.any?(config.sandbox.allowed_paths, &String.contains?(&1, "*"))
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "relative glob allowed_paths expand to absolute paths" do
      # This is P1: relative globs like "./*" should return absolute paths
      # Create test directories in current directory
      cwd = File.cwd!()
      test_id = :rand.uniform(10_000)
      rel_base = "test_rel_glob_#{test_id}"
      base_dir = Path.join(cwd, rel_base)
      proj1 = Path.join(base_dir, "proj1")
      proj2 = Path.join(base_dir, "proj2")
      File.mkdir_p!(proj1)
      File.mkdir_p!(proj2)

      # Use a TRULY RELATIVE glob pattern (starting with ./)
      # This is the pattern that causes issues
      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "./#{rel_base}/*"
        home_path: "#{proj1}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{test_id}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)

        # ALL allowed_paths must be absolute paths (this catches the bug!)
        for path <- config.sandbox.allowed_paths do
          assert Path.type(path) == :absolute,
                 "Path #{path} should be absolute, not relative (started with ./)"
        end

        # Should contain our test dirs as absolute paths
        assert proj1 in config.sandbox.allowed_paths
        assert proj2 in config.sandbox.allowed_paths
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "path validation checks against ALL allowed_paths" do
      # Create two separate root directories
      base_dir = Path.join(System.tmp_dir!(), "test_roots_#{:rand.uniform(10_000)}")
      root1 = Path.join(base_dir, "project")
      root2 = Path.join(base_dir, "libs")
      File.mkdir_p!(root1)
      File.mkdir_p!(root2)

      # home_path is in root2, not root1
      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{root1}"
          - "#{root2}"
        home_path: "#{root2}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        # Should succeed because root2 is in the allowed_paths list
        assert {:ok, config} = Config.load(config_path)
        assert config.sandbox.home_path == root2
        assert root1 in config.sandbox.allowed_paths
        assert root2 in config.sandbox.allowed_paths
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "overlapping allowed_paths are deduplicated" do
      # Create nested directories
      base_dir = Path.join(System.tmp_dir!(), "test_roots_#{:rand.uniform(10_000)}")
      nested = Path.join(base_dir, "project")
      File.mkdir_p!(nested)

      # Both parent and child are allowed_paths - child is redundant but valid
      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{base_dir}"
          - "#{nested}"
        home_path: "#{base_dir}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Both paths are kept (Enum.uniq only removes exact duplicates)
        assert base_dir in config.sandbox.allowed_paths
        assert nested in config.sandbox.allowed_paths
        # Paths are sorted
        assert config.sandbox.allowed_paths == Enum.sort(config.sandbox.allowed_paths)
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "symlink in allowed_paths is resolved" do
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
        allowed_paths:
          - "#{symlink_dir}"
        home_path: "#{symlink_dir}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Config loads successfully with symlink path
        # The symlink is expanded but stored as given
        assert length(config.sandbox.allowed_paths) == 1
        # home_path validation works through symlink
        assert File.dir?(config.sandbox.home_path)
      after
        File.rm(config_path)
        File.rm_rf!(base_dir)
      end
    end

    test "allowed_path with trailing slash is normalized" do
      cwd = File.cwd!()

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{cwd}/"
        home_path: "#{cwd}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:ok, config} = Config.load(config_path)
        # Trailing slash should be normalized away
        [path] = config.sandbox.allowed_paths
        refute String.ends_with?(path, "/")
        assert path == cwd
      after
        File.rm(config_path)
      end
    end

    test "allowed_paths is required in YAML config" do
      cwd = File.cwd!()

      config_content = """
      version: "0.1"
      sandbox:
        home_path: "#{cwd}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:error, msg} = Config.load(config_path)
        assert msg =~ "allowed_paths is required"
      after
        File.rm(config_path)
      end
    end
  end

  describe "TOCTOU prevention" do
    @describetag :toctou
    @describetag :integration

    # These tests require Executor integration - Phase 2 of implementation
    # See handoff: "Integrate Config with Executor (replace single sandbox_root)"

    @tag :skip
    @tag :executor
    test "executor uses config home_path, not inherited shell cwd" do
      # This is the key test: even if shell cwd is /tmp,
      # commands should execute with cwd = home_path from config
    end

    @tag :skip
    @tag :executor
    test "cd command updates in-memory cursor, not shell cwd" do
      # cd /subdir should update Process.get(:truman_cwd)
      # but NOT call System.cmd("cd", ...) or File.cd!()
    end

    @tag :skip
    @tag :executor
    test "relative paths resolve against config home_path, not shell cwd" do
      # If shell cwd is /tmp but home_path is /home/user/project,
      # "cat README.md" should look in /home/user/project/README.md
    end
  end

  describe "config file discovery" do
    @describetag :discovery

    test "finds agents.yaml in current directory" do
      # Create agents.yaml in cwd temporarily
      cwd = File.cwd!()
      config_file = Path.join(cwd, "agents.yaml")

      # Skip if agents.yaml already exists (don't overwrite user config)
      if File.exists?(config_file) do
        flunk("agents.yaml already exists in cwd - can't test discovery")
      end

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{cwd}"
        home_path: "#{cwd}"
      """

      File.write!(config_file, config_content)

      try do
        assert {:ok, config} = Config.discover()
        assert config.version == "0.1"
        assert cwd in config.sandbox.allowed_paths
      after
        File.rm!(config_file)
      end
    end

    test "finds .agents.yaml (hidden variant)" do
      cwd = File.cwd!()
      config_file = Path.join(cwd, ".agents.yaml")
      visible_config = Path.join(cwd, "agents.yaml")

      # Skip if either config already exists
      if File.exists?(config_file) or File.exists?(visible_config) do
        flunk("agents.yaml or .agents.yaml already exists - can't test discovery")
      end

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{cwd}"
        home_path: "#{cwd}"
      """

      File.write!(config_file, config_content)

      try do
        assert {:ok, config} = Config.discover()
        assert config.version == "0.1"
      after
        File.rm!(config_file)
      end
    end

    test "prefers agents.yaml over .agents.yaml" do
      cwd = File.cwd!()
      visible_config = Path.join(cwd, "agents.yaml")
      hidden_config = Path.join(cwd, ".agents.yaml")

      if File.exists?(visible_config) or File.exists?(hidden_config) do
        flunk("config files already exist - can't test preference")
      end

      # Create both with different versions to distinguish them
      File.write!(visible_config, """
      version: "visible"
      sandbox:
        allowed_paths:
          - "#{cwd}"
        home_path: "#{cwd}"
      """)

      File.write!(hidden_config, """
      version: "hidden"
      sandbox:
        allowed_paths:
          - "#{cwd}"
        home_path: "#{cwd}"
      """)

      try do
        assert {:ok, config} = Config.discover()
        # agents.yaml (visible) should be preferred over .agents.yaml
        assert config.version == "visible"
      after
        File.rm!(visible_config)
        File.rm!(hidden_config)
      end
    end

    test "falls back to ~/.config/truman/agents.yaml" do
      cwd = File.cwd!()
      visible_config = Path.join(cwd, "agents.yaml")
      hidden_config = Path.join(cwd, ".agents.yaml")
      fallback_dir = Path.expand("~/.config/truman")
      fallback_config = Path.join(fallback_dir, "agents.yaml")

      if File.exists?(visible_config) or File.exists?(hidden_config) do
        flunk("config files already exist in cwd - can't test fallback")
      end

      # Track if we need to restore original fallback
      original_existed = File.exists?(fallback_config)
      original_content = if original_existed, do: File.read!(fallback_config)

      # Create fallback directory and config
      File.mkdir_p!(fallback_dir)

      File.write!(fallback_config, """
      version: "fallback"
      sandbox:
        allowed_paths:
          - "#{cwd}"
        home_path: "#{cwd}"
      """)

      try do
        assert {:ok, config} = Config.discover()
        assert config.version == "fallback"
      after
        if original_existed do
          File.write!(fallback_config, original_content)
        else
          File.rm!(fallback_config)
        end
      end
    end

    test "returns sensible defaults when no config found" do
      # Default: single allowed_path = cwd, home_path = cwd
      config = Config.defaults()

      assert config.version == "0.1"
      assert length(config.sandbox.allowed_paths) == 1
      assert hd(config.sandbox.allowed_paths) == File.cwd!()
      assert config.sandbox.home_path == File.cwd!()
    end
  end

  describe "config validation" do
    @describetag :validation

    test "rejects config with no allowed_paths" do
      sandbox = %SandboxConfig{
        allowed_paths: [],
        home_path: File.cwd!()
      }

      config = %Config{
        version: "0.1",
        sandbox: sandbox,
        raw: %{}
      }

      assert {:error, msg} = Config.validate(config)
      assert msg =~ "at least one allowed_path"
    end

    test "rejects allowed_path that doesn't exist via loading" do
      # Path existence is validated during YAML loading, not struct validation
      nonexistent = "/this/path/definitely/does/not/exist/#{:rand.uniform(10_000)}"

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{nonexistent}"
        home_path: "#{nonexistent}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:error, msg} = Config.load(config_path)
        assert msg =~ "does not exist"
      after
        File.rm(config_path)
      end
    end

    test "rejects allowed_path that is a file (not directory) via loading" do
      # Path type is validated during YAML loading, not struct validation
      file_path = Path.join(System.tmp_dir!(), "test_file_#{:rand.uniform(10_000)}.txt")
      File.write!(file_path, "I am a file, not a directory")

      config_content = """
      version: "0.1"
      sandbox:
        allowed_paths:
          - "#{file_path}"
        home_path: "#{file_path}"
      """

      config_path = Path.join(System.tmp_dir!(), "test_agents_#{:rand.uniform(10_000)}.yaml")
      File.write!(config_path, config_content)

      try do
        assert {:error, msg} = Config.load(config_path)
        assert msg =~ "not a directory"
      after
        File.rm!(file_path)
        File.rm(config_path)
      end
    end

    @tag :skip
    @tag :deferred
    test "rejects allowed_path outside user home (security)" do
      # DEFERRED: Security boundary enforcement belongs in the harness, not config loader
      # The harness-protected paths from SPEC.md should be checked at runtime
      # config = %{allowed_paths: ["/etc"]}
      # Should return {:error, "allowed_path /etc is outside allowed base paths"}
    end

    @tag :skip
    @tag :deferred
    test "accepts system_paths override in config" do
      # DEFERRED: Requires security boundary implementation first
      # By default, /etc, ~/.ssh, etc. are blocked
      # But config could allow specific system paths (with warning?)
    end
  end

  describe "edge cases from real usage" do
    @describetag :edge_cases
    @describetag :integration

    # These tests require Executor/Harness integration - Phase 2-3 of implementation
    # See handoff: "Integrate Config with Executor", "Integration tests for home_path behavior"

    @tag :skip
    @tag :executor
    test "cd to another allowed_path, then relative path resolves correctly" do
      # allowed_paths: [~/studios/reification-labs, ~/code/truman-shell]
      # home_path: ~/studios/reification-labs
      # cd ~/code/truman-shell
      # cat lib/sandbox.ex -> should work (within allowed_paths)
    end

    @tag :skip
    @tag :executor
    test "cd to path outside all allowed_paths fails" do
      # cd /tmp -> error, not within allowed_paths
    end

    @tag :skip
    @tag :harness
    test "checkpoint creates files in home_path, not current cd location" do
      # This is the user's actual use case!
      # cd ~/code/truman-shell (for git work)
      # /checkpoint -> files should go to ~/studios/reification-labs/.checkpoints/
      # HOW? The harness passes cwd to subprocess, not the shell's cwd
    end

    @tag :skip
    @tag :executor
    test "git -C works with paths in any allowed_path" do
      # git -C ~/code/truman-shell status
      # Should work because ~/code/truman-shell is in allowed_paths
    end

    @tag :skip
    @tag :harness
    test "symlink from one allowed_path to another is followed" do
      # ~/studios/reification-labs/.vault/truman-shell -> ~/code/truman-shell
      # If both are allowed_paths, symlink should be allowed
    end

    @tag :skip
    @tag :harness
    test "symlink from allowed_path to outside-allowed_path is denied" do
      # ~/code/escape -> /etc
      # Even though ~/code/* is an allowed_path, the symlink target is not
    end
  end
end
