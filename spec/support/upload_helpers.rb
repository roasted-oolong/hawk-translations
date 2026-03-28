# spec/support/upload_helpers.rb
#
# Helpers for system specs that need to attach file uploads.
#
# file_fixture_path(filename, content)
#   Writes `content` to a temp file named `filename` and returns the absolute
#   path so Capybara's `attach_file` can find it. Files are cleaned up after
#   each example via an after-hook registered here.

module UploadHelpers
  # Write content to a named temp file and return its path.
  # The file lives for the duration of the example.
  def file_fixture_path(filename, content)
    dir = Rails.root.join("tmp", "upload_fixtures")
    FileUtils.mkdir_p(dir)
    path = dir.join(filename).to_s
    File.write(path, content, encoding: "UTF-8")
    # Track for cleanup
    @_upload_fixture_paths ||= []
    @_upload_fixture_paths << path
    path
  end
end

RSpec.configure do |config|
  config.include UploadHelpers, type: :system

  config.after(:each, type: :system) do
    Array(@_upload_fixture_paths).each do |path|
      File.delete(path) if File.exist?(path)
    end
    @_upload_fixture_paths = nil
  end
end
