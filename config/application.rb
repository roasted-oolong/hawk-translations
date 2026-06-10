require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# =============================================================================
# Rails 8.1.2 + Ruby 3.4 incompatibility fix
#
# Every class that ActiveSupport's blank.rb reopens ends up with `presence`
# marked as private in its own method table, even though blank.rb never
# defines presence on those classes. Object#presence (public) is shadowed
# by the private entry in each subclass's method table.
#
# Fix: define presence explicitly on every class blank.rb reopens so each
# class has its own PUBLIC method table entry.
#
# Remove when upgrading to a Rails version that fixes this.
# =============================================================================
[NilClass, FalseClass, TrueClass, Array, Hash, Symbol, String,
 Numeric, Integer, Float, Time, Object].each do |klass|
  klass.class_eval do
    def presence
      present? ? self : nil
    end
  end
end

module Hawk
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Use SQL format for schema dumps so PostgreSQL-specific types (e.g.
    # vector(1024) from pgvector) are preserved correctly. The default
    # schema.rb format cannot serialize custom column types.
    config.active_record.schema_format = :sql
  end
end
