# ---------------------------------------------------------------------------
# TranslationConfig
#
# Single validated read point for every env var the Ruby translation backend
# seam (R1) depends on. Names are reused verbatim from Python's config.py —
# no Ruby-only var invented for a concept Python already names.
#
# Two independent axes (TRANSLATION_BACKEND, CALIBRATION_BACKEND) rather than
# one parsed mapping, matching config.py's own idiom.
#
# CLAUDE_BIN is resolved once here, to an absolute path, before any
# subprocess spawn — never delegated to the child via PATH. If unset, the
# default "claude" is resolved via a PATH lookup performed by this process's
# own controlled environment. If set, it must already be an absolute,
# executable path; no further PATH search happens on top of it.
# ---------------------------------------------------------------------------
class TranslationConfig
  class ConfigError < StandardError; end

  VALID_BACKENDS = %w[local claude_code].freeze

  attr_reader :translation_backend, :calibration_backend, :llm_base_url, :llm_api_key,
              :translation_model, :translation_max_budget_usd, :claude_bin

  def self.from_env(env = ENV)
    new(env)
  end

  def initialize(env = ENV)
    @translation_backend        = validate_backend(env, "TRANSLATION_BACKEND")
    @calibration_backend        = validate_backend(env, "CALIBRATION_BACKEND")
    @llm_base_url                = env.fetch("LLM_BASE_URL", "http://localhost:11434/v1")
    @llm_api_key                 = env.fetch("LLM_API_KEY", "local")
    @translation_model           = env.fetch("TRANSLATION_MODEL", "opus")
    @translation_max_budget_usd = validate_budget(env)
    @claude_bin                  = resolve_claude_bin(env)
  end

  private

  def validate_backend(env, var_name)
    value = env.fetch(var_name, "claude_code")
    unless VALID_BACKENDS.include?(value)
      raise ConfigError,
            "#{var_name}=#{value.inspect} is not a recognized backend " \
            "(expected #{VALID_BACKENDS.join(' or ')})"
    end
    value
  end

  def validate_budget(env)
    raw = env.fetch("TRANSLATION_MAX_BUDGET_USD", "3.00")
    value = Float(raw, exception: false)
    if value.nil? || value.negative?
      raise ConfigError,
            "TRANSLATION_MAX_BUDGET_USD=#{raw.inspect} must be a non-negative decimal"
    end
    value
  end

  def resolve_claude_bin(env)
    explicitly_set = env.key?("CLAUDE_BIN")
    raw = env.fetch("CLAUDE_BIN", "claude")

    if explicitly_set
      unless raw.start_with?("/")
        raise ConfigError,
              "CLAUDE_BIN=#{raw.inspect} must be an absolute path, not a relative one"
      end
      unless File.file?(raw) && File.executable?(raw)
        raise ConfigError, "CLAUDE_BIN=#{raw.inspect} is not an executable file"
      end
      raw
    else
      which(env, raw) || raise(
        ConfigError,
        "claude CLI not found on PATH (looked for #{raw.inspect}); " \
        "set CLAUDE_BIN to its absolute path"
      )
    end
  end

  # PATH lookup performed once, against this process's own env — never
  # delegated to the child, and PATH itself is never forwarded to it.
  def which(env, command)
    env.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
      candidate = File.join(dir, command)
      return candidate if File.file?(candidate) && File.executable?(candidate)
    end
    nil
  end
end
