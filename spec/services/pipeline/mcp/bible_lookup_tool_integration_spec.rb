# Integration tier of R3's testing strategy: a real MCP::Server wired to the
# real adapter, dispatched via #handle directly (bypassing stdio/transport)
# against a real database — proves the JSON-RPC shape and BibleSearchService
# call both work, no LLM involved.
require "rails_helper"

RSpec.describe "Pipeline::Mcp::BibleLookupTool integration" do
  let(:organization)  { create(:organization) }
  let!(:novel)         { create(:novel, organization: organization, directory_name: "idols-rewind") }
  let(:fake_vector)    { Array.new(512, 0.01) }
  let(:server_context) { Pipeline::Mcp::ServerContext.new(novel_directory_name: "idols-rewind") }
  let(:server) do
    MCP::Server.new(
      name: "hawk-skills",
      tools: [ Pipeline::Mcp::BibleLookupTool ],
      server_context: server_context
    )
  end

  before do
    allow(VoyageClient).to receive(:embed).and_return(fake_vector)
  end

  def embed!(record)
    BibleEmbedding.upsert(
      {
        embeddable_type: record.class.name,
        embeddable_id:   record.id,
        novel_id:        record.novel_id,
        organization_id: record.novel.organization_id,
        content_hash:    Digest::SHA256.hexdigest(record.embeddable_text),
        embedding:       "[#{fake_vector.join(',')}]",
        search_text:     Arel.sql(
          "to_tsvector('simple', #{ActiveRecord::Base.connection.quote(record.embeddable_text)})"
        ),
        created_at:      Time.current,
        updated_at:      Time.current
      },
      unique_by: %i[embeddable_type embeddable_id],
      update_only: %i[content_hash embedding search_text]
    )
  end

  def call_tool(name:, arguments:)
    server.handle({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: name, arguments: arguments }
    })
  end

  it "lists bible_lookup as an available tool" do
    response = server.handle({ jsonrpc: "2.0", id: 1, method: "tools/list" })

    names = response[:result][:tools].map { |t| t[:name] }
    expect(names).to eq([ "bible_lookup" ])
  end

  it "round-trips a real tool call through JSON-RPC to a real BibleSearchService and back" do
    character = create(:bible_character, novel: novel, name: "Hyuk Kang", role: "Protagonist")
    embed!(character)

    response = call_tool(name: "bible_lookup", arguments: { query: "Hyuk Kang" })

    text = response[:result][:content].first[:text]
    expect(text).to include("[Character]")
    expect(text).to include("Name: Hyuk Kang")
    expect(response[:result][:isError]).to be_falsey
  end

  it "fails at the SDK's own dispatch layer for an unregistered tool name, before any adapter code runs" do
    response = call_tool(name: "not_a_real_tool", arguments: { query: "x" })

    expect(response[:error][:code]).to eq(JsonRpcHandler::ErrorCode::INVALID_PARAMS)
  end

  it "rejects a call missing the required query argument before the adapter ever runs" do
    expect(Pipeline::Skills::BibleLookup).not_to receive(:new)

    response = call_tool(name: "bible_lookup", arguments: {})

    expect(response[:result][:isError]).to eq(true)
  end
end
