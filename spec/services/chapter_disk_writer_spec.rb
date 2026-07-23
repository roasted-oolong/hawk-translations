require "rails_helper"

RSpec.describe ChapterDiskWriter do
  let(:novel_dir) { Dir.mktmpdir }
  let(:novel)     { create(:novel, directory_name: File.basename(novel_dir)) }
  let(:chapter)   { create(:chapter, novel: novel, number: 3) }
  let(:output_path) { File.join(novel_dir, "chapters", "Chapter 3.txt") }

  before do
    @orig_root = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
  end

  after do
    ENV["HAWK_PROJECT_ROOT"] = @orig_root
    FileUtils.rm_rf(novel_dir)
  end

  it "writes the chapter text to disk under chapters/Chapter <N>.txt" do
    described_class.new(novel).write(chapter, "Revised text.")
    expect(File.read(output_path, encoding: "UTF-8")).to eq("Revised text.")
  end

  it "creates the chapters directory if it doesn't exist yet" do
    described_class.new(novel).write(chapter, "Revised text.")
    expect(File).to exist(File.join(novel_dir, "chapters"))
  end

  it "overwrites an existing chapter file rather than appending" do
    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, "Original machine translation.")

    described_class.new(novel).write(chapter, "Revised text.")

    expect(File.read(output_path, encoding: "UTF-8")).to eq("Revised text.")
  end

  it "does not leave a stray temp file behind after a successful write" do
    described_class.new(novel).write(chapter, "Revised text.")
    leftovers = Dir.glob(File.join(novel_dir, "chapters", "*.tmp"))
    expect(leftovers).to be_empty
  end

  it "raises and cleans up the temp file if the rename fails" do
    writer = described_class.new(novel)
    allow(File).to receive(:rename).and_raise(Errno::ENOSPC)

    expect { writer.write(chapter, "Revised text.") }.to raise_error(Errno::ENOSPC)

    leftovers = Dir.glob(File.join(novel_dir, "chapters", "*.tmp"))
    expect(leftovers).to be_empty
  end

  it "raises clearly when HAWK_PROJECT_ROOT is not set" do
    ENV["HAWK_PROJECT_ROOT"] = nil
    expect { described_class.new(novel).write(chapter, "text") }
      .to raise_error(/HAWK_PROJECT_ROOT/)
  end
end
