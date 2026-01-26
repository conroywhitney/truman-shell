defmodule TrumanShell.Config do
  @moduledoc """
  Configuration loading for agents.yaml.

  Discovers, loads, and parses the agents.yaml config file. Delegates sandbox
  parsing and validation to `TrumanShell.Config.Sandbox`.

  ## File Discovery

  Config files are searched in order:
  1. `./agents.yaml`
  2. `./.agents.yaml`
  3. `~/.config/truman/agents.yaml`

  If no config is found, defaults to cwd for both allowed_paths and home_path.

  ## Example Config

      # agents.yaml
      version: "0.1"

      sandbox:
        allowed_paths:
          - "~/studios/reification-labs"
          - "~/code/*"
        home_path: "~/studios/reification-labs"

  See `TrumanShell.Config.Sandbox` for sandbox field documentation.
  """

  alias TrumanShell.Config
  alias TrumanShell.DomePath

  @type t :: %__MODULE__{
          version: String.t(),
          sandbox: Config.Sandbox.t(),
          raw: map()
        }

  defstruct [
    :version,
    :sandbox,
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
      iex> %TrumanShell.Config.Sandbox{} = config.sandbox
      iex> is_list(config.sandbox.allowed_paths)
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
  - Single allowed_path: current working directory
  - home_path: same as allowed_path

  Note: This uses File.cwd!() which is the shell's cwd at load time.
  For production use, prefer explicit config files.

  ## Examples

      iex> config = TrumanShell.Config.defaults()
      iex> length(config.sandbox.allowed_paths) == 1
      true

  """
  @spec defaults() :: t()
  def defaults do
    %__MODULE__{
      version: "0.1",
      sandbox: Config.Sandbox.defaults(),
      raw: %{}
    }
  end

  @doc """
  Validates a configuration struct.

  Delegates sandbox validation to `Config.Sandbox.validate/1` which checks:
  - allowed_paths is not empty
  - home_path is within one of the allowed_paths

  Note: Path existence validation is done during `from_yaml/1` loading.
  This function validates struct invariants only.

  ## Examples

      iex> sandbox = TrumanShell.Config.Sandbox.defaults()
      iex> config = %TrumanShell.Config{version: "0.1", sandbox: sandbox, raw: %{}}
      iex> {:ok, ^config} = TrumanShell.Config.validate(config)

  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{sandbox: %Config.Sandbox{} = sandbox} = config) do
    case Config.Sandbox.validate(sandbox) do
      {:ok, _} -> {:ok, config}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(%__MODULE__{sandbox: nil}) do
    {:error, "config.sandbox is required"}
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
        {:ok, DomePath.expand(found)}
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
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, "invalid YAML: #{inspect(reason)}"}
    end
  end

  defp build_config(parsed) when is_map(parsed) do
    sandbox_yaml = Map.get(parsed, "sandbox", %{})

    case Config.Sandbox.from_yaml(sandbox_yaml) do
      {:ok, sandbox} ->
        {:ok,
         %__MODULE__{
           version: Map.get(parsed, "version", "0.1"),
           sandbox: sandbox,
           raw: parsed
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_config(_), do: {:error, "config must be a YAML map"}

  # Expand ~ to user's home directory (for config file paths)
  defp expand_user_home("~"), do: System.user_home!()
  defp expand_user_home("~/" <> rest), do: DomePath.join(System.user_home!(), rest)
  defp expand_user_home(path), do: path
end
