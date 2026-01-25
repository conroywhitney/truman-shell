defmodule TrumanShell.Config do
  @moduledoc """
  Configuration loading and validation for agents.yaml.

  The agents.yaml file defines:
  - `sandbox.roots` - Directories the agent can access (boundaries)
  - `sandbox.default_cwd` - Working directory for command execution (home base)

  ## Key Concepts

  **Roots (Boundaries)**: Where the agent CAN access. Multiple roots are supported,
  with glob expansion (e.g., `~/code/*` expands to all subdirectories).

  **Default CWD (Home Base)**: Where outputs land. Commands are spawned with this
  as their working directory, eliminating TOCTOU race conditions. Even if you
  `cd ~/code/truman-shell` for git operations, `/checkpoint` creates files in
  the homebase.

  ## File Discovery

  Config files are searched in order:
  1. `./agents.yaml`
  2. `./.agents.yaml`
  3. `~/.config/truman/agents.yaml`

  If no config is found, sensible defaults are used (single root = cwd).

  ## Example Config

      # agents.yaml
      version: "0.1"

      sandbox:
        roots:
          - "~/studios/reification-labs"
          - "~/code/*"
        default_cwd: "~/studios/reification-labs"

  """

  # Note: We use expand_user_home/1 instead of expand_user_home/2 here.
  # expand_user_home/2 expands ~ to sandbox_root (agent's home).
  # For config loading, we expand ~ to the user's actual home.

  @type t :: %__MODULE__{
          version: String.t(),
          roots: [String.t()],
          default_cwd: String.t(),
          # Future: per-agent overrides, file permissions, execute permissions
          raw: map()
        }

  defstruct [
    :version,
    :roots,
    :default_cwd,
    :raw
  ]

  @config_filenames ["agents.yaml", ".agents.yaml"]
  @fallback_config_path "~/.config/truman/agents.yaml"

  @doc """
  Discovers and loads configuration from standard locations.

  Searches for config files in order:
  1. Current directory: `agents.yaml`, `.agents.yaml`
  2. Fallback: `~/.config/truman/agents.yaml`

  Returns defaults if no config file is found.

  ## Examples

      iex> {:ok, config} = TrumanShell.Config.discover()
      iex> is_list(config.roots)
      true

  """
  @spec discover() :: {:ok, t()} | {:error, String.t()}
  def discover do
    case find_config_file() do
      {:ok, path} -> load(path)
      :not_found -> {:ok, defaults()}
    end
  end

  @doc """
  Loads configuration from a specific file path.

  The path is expanded (~ handling) before reading.

  ## Examples

      iex> TrumanShell.Config.load("/nonexistent/agents.yaml")
      {:error, "config file not found: /nonexistent/agents.yaml"}

  """
  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(path) do
    expanded_path = expand_user_home(path)

    with {:ok, content} <- read_file(expanded_path),
         {:ok, parsed} <- parse_yaml(content),
         {:ok, config} <- build_config(parsed) do
      validate(config)
    end
  end

  @doc """
  Returns default configuration when no config file is found.

  Default behavior:
  - Single root: current working directory
  - default_cwd: same as root

  Note: This uses File.cwd!() which is the shell's cwd at load time.
  For production use, prefer explicit config files.

  ## Examples

      iex> config = TrumanShell.Config.defaults()
      iex> length(config.roots) == 1
      true

  """
  @spec defaults() :: t()
  def defaults do
    cwd = File.cwd!()

    %__MODULE__{
      version: "0.1",
      roots: [cwd],
      default_cwd: cwd,
      raw: %{}
    }
  end

  @doc """
  Validates a configuration struct.

  Checks:
  - All roots exist and are directories
  - default_cwd is within one of the roots
  - Paths are resolved (no unresolved ~ or globs)

  ## Examples

      iex> config = %TrumanShell.Config{version: "0.1", roots: ["/nonexistent"], default_cwd: "/nonexistent", raw: %{}}
      iex> {:error, msg} = TrumanShell.Config.validate(config)
      iex> msg =~ "does not exist"
      true

  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    with :ok <- validate_roots(config.roots),
         :ok <- validate_default_cwd(config.default_cwd, config.roots) do
      {:ok, config}
    end
  end

  # --- Private Functions ---

  defp find_config_file do
    # Check current directory first
    case Enum.find(@config_filenames, &File.exists?/1) do
      nil ->
        # Check fallback location
        fallback = expand_user_home(@fallback_config_path)

        if File.exists?(fallback) do
          {:ok, fallback}
        else
          :not_found
        end

      found ->
        {:ok, Path.expand(found)}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, "config file not found: #{path}"}
      {:error, reason} -> {:error, "failed to read config: #{inspect(reason)}"}
    end
  end

  defp parse_yaml(content) do
    case Code.ensure_loaded(YamlElixir) do
      {:module, YamlElixir} ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, "invalid YAML: #{inspect(reason)}"}
        end

      {:error, _} ->
        {:error, "yaml_elixir not available - add to deps"}
    end
  end

  defp build_config(parsed) when is_map(parsed) do
    sandbox = Map.get(parsed, "sandbox", %{})
    raw_roots = Map.get(sandbox, "roots", ["."])
    raw_default_cwd = Map.get(sandbox, "default_cwd", List.first(raw_roots, "."))

    # Expand ~ and globs in roots
    expanded_roots = expand_roots(raw_roots)

    # Expand ~ in default_cwd (resolve relative to first root)
    default_cwd = expand_default_cwd(raw_default_cwd, expanded_roots)

    {:ok,
     %__MODULE__{
       version: Map.get(parsed, "version", "0.1"),
       roots: expanded_roots,
       default_cwd: default_cwd,
       raw: parsed
     }}
  end

  defp build_config(_), do: {:error, "config must be a YAML map"}

  defp expand_roots(raw_roots) when is_list(raw_roots) do
    raw_roots
    |> Enum.flat_map(&expand_root/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp expand_root(root) do
    expanded = expand_user_home(root)

    if String.contains?(expanded, "*") do
      # Glob expansion
      expanded
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
    else
      [Path.expand(expanded)]
    end
  end

  defp expand_default_cwd(raw_cwd, roots) do
    expanded = expand_user_home(raw_cwd)

    # Absolute path
    if Path.type(expanded) == :absolute do
      Path.expand(expanded)
    else
      # Relative path - resolve against first root
      first_root = List.first(roots, File.cwd!())
      Path.expand(expanded, first_root)
    end
  end

  defp validate_roots([]) do
    {:error, "config must have at least one root"}
  end

  defp validate_roots(roots) do
    Enum.reduce_while(roots, :ok, fn root, :ok ->
      cond do
        not File.exists?(root) ->
          {:halt, {:error, "root does not exist: #{root}"}}

        not File.dir?(root) ->
          {:halt, {:error, "root is not a directory: #{root}"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_default_cwd(default_cwd, roots) do
    cond do
      not File.exists?(default_cwd) ->
        {:error, "default_cwd does not exist: #{default_cwd}"}

      not File.dir?(default_cwd) ->
        {:error, "default_cwd is not a directory: #{default_cwd}"}

      not within_any_root?(default_cwd, roots) ->
        {:error, "default_cwd must be within one of the roots: #{default_cwd}"}

      true ->
        :ok
    end
  end

  defp within_any_root?(path, roots) do
    resolved_path = resolve_real_path(path)

    Enum.any?(roots, fn root ->
      resolved_root = resolve_real_path(root)
      String.starts_with?(resolved_path, resolved_root <> "/") or resolved_path == resolved_root
    end)
  end

  # Expand ~ to user's home directory (for config paths, not agent paths)
  defp expand_user_home("~"), do: System.user_home!()
  defp expand_user_home("~/" <> rest), do: Path.join(System.user_home!(), rest)
  defp expand_user_home(path), do: path

  # Resolve symlinks to get real path
  defp resolve_real_path(path) do
    case File.read_link(path) do
      {:ok, target} ->
        # Symlink - resolve it
        if Path.type(target) == :absolute do
          resolve_real_path(target)
        else
          path |> Path.dirname() |> Path.join(target) |> resolve_real_path()
        end

      {:error, _} ->
        # Not a symlink, just expand
        Path.expand(path)
    end
  end
end
