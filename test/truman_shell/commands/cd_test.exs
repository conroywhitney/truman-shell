defmodule TrumanShell.Commands.CdTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Cd
  alias TrumanShell.Commands.Context
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  # Helper to build context with home_path as home and given current_path
  defp build_ctx(current_path, home_path \\ File.cwd!()) do
    config = %SandboxConfig{allowed_paths: [home_path], home_path: home_path}
    %Context{current_path: current_path, sandbox_config: config}
  end

  describe "handle/2" do
    test "changes to subdirectory and returns set_cwd" do
      ctx = build_ctx(File.cwd!())

      {:ok, "", ctx: new_ctx} = Cd.handle(["lib"], ctx)

      assert String.ends_with?(new_ctx.current_path, "/lib")
    end

    test "changes to nested subdirectory" do
      ctx = build_ctx(File.cwd!())

      {:ok, "", ctx: new_ctx} = Cd.handle(["lib/truman_shell"], ctx)

      assert String.ends_with?(new_ctx.current_path, "/lib/truman_shell")
    end

    test "returns to home_path with no args" do
      home_path = File.cwd!()
      current = Path.join(home_path, "lib/truman_shell")
      ctx = build_ctx(current, home_path)

      {:ok, "", ctx: new_ctx} = Cd.handle([], ctx)

      assert new_ctx.current_path == home_path
    end

    # NOTE: Tilde expansion is now handled by Stages.Expander before Cd.handle.
    # These tests pass pre-expanded paths to test Cd.handle behavior.

    test "navigates to home_path (pre-expanded from ~)" do
      home_path = File.cwd!()
      current = Path.join(home_path, "lib/truman_shell")
      ctx = build_ctx(current, home_path)

      # ~ is expanded to home_path by Expander before reaching Cd
      {:ok, "", ctx: new_ctx} = Cd.handle([home_path], ctx)

      assert new_ctx.current_path == home_path
    end

    test "navigates to subdir (pre-expanded from ~/lib)" do
      home_path = File.cwd!()
      current = Path.join(home_path, "lib/truman_shell")
      ctx = build_ctx(current, home_path)

      # ~/lib is expanded to home_path/lib by Expander before reaching Cd
      expanded_path = Path.join(home_path, "lib")
      {:ok, "", ctx: new_ctx} = Cd.handle([expanded_path], ctx)

      assert new_ctx.current_path == Path.join(home_path, "lib")
    end

    test "returns error for nonexistent path (pre-expanded from ~/nonexistent)" do
      home_path = File.cwd!()
      ctx = build_ctx(home_path, home_path)

      # ~/nonexistent is expanded to home_path/nonexistent by Expander
      expanded_path = Path.join(home_path, "nonexistent")
      result = Cd.handle([expanded_path], ctx)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "navigates up with .." do
      home_path = File.cwd!()
      current = Path.join(home_path, "lib/truman_shell")
      ctx = build_ctx(current, home_path)

      {:ok, "", ctx: new_ctx} = Cd.handle([".."], ctx)

      assert new_ctx.current_path == Path.join(home_path, "lib")
    end

    test "returns error when .. would escape sandbox" do
      home_path = File.cwd!()
      ctx = build_ctx(home_path, home_path)

      result = Cd.handle([".."], ctx)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "returns error for non-existent directory" do
      ctx = build_ctx(File.cwd!())

      result = Cd.handle(["nonexistent"], ctx)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "rejects absolute paths outside sandbox (404 principle)" do
      ctx = build_ctx(File.cwd!())

      result = Cd.handle(["/etc"], ctx)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
      # Must NOT reveal that the path exists
      refute msg =~ "permission"
      refute msg =~ "Permission"
    end

    test "returns error for file (not directory)" do
      ctx = build_ctx(File.cwd!())

      result = Cd.handle(["mix.exs"], ctx)

      assert {:error, msg} = result
      assert msg =~ "Not a directory"
    end

    # === SECURITY EDGE CASES ===
    # These tests verify sandbox boundaries cannot be escaped via tilde paths

    test "~/.. cannot escape sandbox (stays at root)" do
      home_path = File.cwd!()
      ctx = build_ctx(home_path, home_path)

      result = Cd.handle(["~/.."], ctx)

      # Should error - can't go above sandbox root
      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "~/../../etc cannot escape sandbox (traversal attack)" do
      home_path = File.cwd!()
      ctx = build_ctx(home_path, home_path)

      result = Cd.handle(["~/../../etc"], ctx)

      # Must block - this is a traversal attack
      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
      # 404 principle - don't reveal /etc exists
      refute msg =~ "permission"
    end

    # NOTE: ~//lib, ~user, etc. tests moved to Stages.ExpanderTest
    # since Expander now handles all tilde expansion before Cd.handle.

    test "navigates with .. within sandbox" do
      home_path = File.cwd!()
      ctx = build_ctx(home_path, home_path)

      # Pre-expanded: ~/lib/../test becomes home_path/lib/../test
      expanded_path = Path.join(home_path, "lib/../test")
      {:ok, "", ctx: new_ctx} = Cd.handle([expanded_path], ctx)

      assert new_ctx.current_path == Path.join(home_path, "test")
    end
  end
end
