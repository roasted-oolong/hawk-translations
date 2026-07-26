require "net/http"
require "json"

# ---------------------------------------------------------------------------
# Pipeline::LocalLlmChat
#
# Ruby port of the "local" backend's HTTP call in src/agent.py#call — a
# single OpenAI-compatible chat-completions request against an Ollama (or
# equivalent) endpoint. Used only by the formatter (R6.5); no streaming, no
# tool use, no MCP — a strictly smaller surface than Pipeline::ClaudeCode, and
# a separate class from it rather than a shared parent, since the two talk to
# different kinds of backends entirely (HTTP API vs. a CLI subprocess).
#
# Knows nothing about prompts, chapters, or formatting — given a system
# prompt, a user message, and connection details, it returns a Result. Callers
# supply model/max_tokens/base_url/api_key explicitly rather than this class
# reading env itself, so it stays testable against a fake HTTP server with no
# env stubbing required.
# ---------------------------------------------------------------------------
module Pipeline
  class LocalLlmChat
    # error_category is nil on success. On failure it's one of:
    # :connection_failed (endpoint unreachable/timed out — the frequent local
    # failure mode when Ollama isn't running), :http_error (non-2xx status),
    # :unparseable_output (response body isn't valid JSON, or lacks the
    # expected choices[0].message.content shape).
    Result = Struct.new(:output, :error_category, :error_message, keyword_init: true) do
      def success?
        error_category.nil?
      end
    end

    def self.call(system_prompt:, user_message:, base_url:, api_key:, model:, max_tokens:, timeout: 1800)
      new(system_prompt: system_prompt, user_message: user_message, base_url: base_url,
          api_key: api_key, model: model, max_tokens: max_tokens, timeout: timeout).call
    end

    def initialize(system_prompt:, user_message:, base_url:, api_key:, model:, max_tokens:, timeout:)
      @system_prompt = system_prompt
      @user_message  = user_message
      @base_url      = base_url
      @api_key       = api_key
      @model         = model
      @max_tokens    = max_tokens
      @timeout       = timeout
    end

    def call
      uri = URI.join("#{@base_url}/", "chat/completions")

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"]  = "application/json"
      request.body = JSON.generate({
        model:      @model,
        max_tokens: @max_tokens,
        messages: [
          { role: "system", content: @system_prompt },
          { role: "user",   content: @user_message }
        ]
      })

      response = begin
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: @timeout, read_timeout: @timeout) do |http|
          http.request(request)
        end
      rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
        return Result.new(error_category: :connection_failed,
                           error_message:  "could not reach #{@base_url}: #{e.class}: #{e.message}")
      end

      unless response.is_a?(Net::HTTPSuccess)
        return Result.new(error_category: :http_error,
                           error_message:  "#{@base_url} returned HTTP #{response.code}: #{response.body.to_s[0, 500]}")
      end

      parse(response.body)
    end

    private

    def parse(body)
      data = JSON.parse(body)
      content = data.dig("choices", 0, "message", "content")

      if content.nil?
        return Result.new(error_category: :unparseable_output,
                           error_message:  "response missing choices[0].message.content: #{body[0, 500]}")
      end

      Result.new(output: content)
    rescue JSON::ParserError
      Result.new(error_category: :unparseable_output,
                 error_message:  "response body was not valid JSON: #{body[0, 500]}")
    end
  end
end
