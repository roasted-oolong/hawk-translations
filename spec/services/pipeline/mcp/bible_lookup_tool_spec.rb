# Unit tier of R3's testing strategy: the adapter's .call tested directly
# as a class method, server_context: stubbed, no real MCP::Server or
# transport involved.
require "rails_helper"

RSpec.describe Pipeline::Mcp::BibleLookupTool do
  describe "tool declaration" do
    it "declares the tool_name and the query/categories schema" do
      expect(described_class.tool_name).to eq("bible_lookup")

      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to eq([ "query" ])
      expect(schema[:properties].keys).to contain_exactly(:query, :categories)
    end

    it "is not a Pipeline::Skill — the mcp gem's tools are class-level, skills stay instance-based" do
      expect(described_class.ancestors).not_to include(Pipeline::Skill)
      expect(described_class.superclass).to eq(MCP::Tool)
    end
  end

  describe ".call" do
    let(:server_context) { Pipeline::Mcp::ServerContext.new(novel_directory_name: "idols-rewind") }

    it "builds a BibleLookup skill from server_context and delegates to #execute" do
      skill = instance_double(Pipeline::Skills::BibleLookup, execute: "[Character]\nName: Hyuk Kang")
      expect(Pipeline::Skills::BibleLookup).to receive(:new)
        .with(novel_directory_name: "idols-rewind").and_return(skill)
      expect(skill).to receive(:execute).with({ query: "Hyuk" })

      described_class.call(server_context: server_context, query: "Hyuk")
    end

    it "wraps the skill's string result in an MCP::Tool::Response with error left at its default (false)" do
      allow(Pipeline::Skills::BibleLookup).to receive(:new)
        .and_return(instance_double(Pipeline::Skills::BibleLookup, execute: "No bible entries found for: x"))

      response = described_class.call(server_context: server_context, query: "x")

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to eq(false)
      expect(response.content).to eq([ { type: "text", text: "No bible entries found for: x" } ])
    end

    it "returns the skill's own error string as ordinary text content, not MCP's isError channel" do
      allow(Pipeline::Skills::BibleLookup).to receive(:new)
        .and_return(instance_double(Pipeline::Skills::BibleLookup, execute: "[bible_lookup error: empty query]"))

      response = described_class.call(server_context: server_context, query: "")

      expect(response.error?).to eq(false)
      expect(response.content).to eq([ { type: "text", text: "[bible_lookup error: empty query]" } ])
    end

    it "redirects $stdout to $stderr for the duration of #execute, restoring it afterward, even on error" do
      real_stdout = $stdout
      seen_stdout_during_execute = nil
      allow(Pipeline::Skills::BibleLookup).to receive(:new).and_return(
        instance_double(Pipeline::Skills::BibleLookup, execute: nil).tap do |skill|
          allow(skill).to receive(:execute) do
            seen_stdout_during_execute = $stdout
            "ok"
          end
        end
      )

      described_class.call(server_context: server_context, query: "x")

      expect(seen_stdout_during_execute).to eq($stderr)
      expect($stdout).to equal(real_stdout)
    end

    it "restores $stdout even if #execute raises" do
      real_stdout = $stdout
      allow(Pipeline::Skills::BibleLookup).to receive(:new).and_return(
        instance_double(Pipeline::Skills::BibleLookup).tap { |s| allow(s).to receive(:execute).and_raise("boom") }
      )

      expect { described_class.call(server_context: server_context, query: "x") }.to raise_error("boom")
      expect($stdout).to equal(real_stdout)
    end

    it "builds a fresh skill instance per call — never memoizes one across calls" do
      built = []
      allow(Pipeline::Skills::BibleLookup).to receive(:new).and_wrap_original do |original, **args|
        skill = original.call(**args)
        allow(skill).to receive(:execute).and_return("ok")
        built << skill
        skill
      end

      described_class.call(server_context: server_context, query: "a")
      described_class.call(server_context: server_context, query: "b")

      expect(built.size).to eq(2)
      expect(built[0]).not_to equal(built[1])
    end
  end
end
