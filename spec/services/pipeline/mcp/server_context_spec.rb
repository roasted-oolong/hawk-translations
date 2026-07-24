require "rails_helper"

RSpec.describe Pipeline::Mcp::ServerContext do
  it "is an immutable value object carrying the novel directory name" do
    context = described_class.new(novel_directory_name: "idols-rewind")

    expect(context.novel_directory_name).to eq("idols-rewind")
    expect(context).to be_frozen
  end

  it "has no attribute writers" do
    context = described_class.new(novel_directory_name: "idols-rewind")

    expect(context).not_to respond_to(:novel_directory_name=)
  end

  it "requires novel_directory_name" do
    expect { described_class.new }.to raise_error(ArgumentError)
  end
end
