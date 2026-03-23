# spec/support/system_spec_helper.rb
#
# Registers the Cuprite driver for system specs and configures Capybara.
# Configures DatabaseCleaner to use truncation for system specs.
#
# Driver: Cuprite (CDP-based, uses Ferrum under the hood to drive Chrome/Chromium).
# See DECISIONS.md for rationale over Playwright / Selenium.
#
# Why truncation for system specs:
#   Cuprite drives a real browser, which makes HTTP requests through Puma in a
#   separate thread with its own database connection. Rails' transactional
#   fixtures wrap each test in a transaction on the test thread's connection —
#   the browser's connection never sees that transaction and its writes are never
#   rolled back. Truncation cleans the database at the OS level after each
#   example, regardless of which connection created the rows.
#
#   All other spec types (model, request) keep the default transaction strategy
#   because they share a single connection with the test thread.
#
# Chrome/Chromium must be installed on the system. In WSL2 development this
# is the Windows Chrome binary exposed via PATH, or the Linux Chromium package.
# In CI this is whatever Chrome version the runner provides.
#
# To run system specs:
#   bundle exec rspec spec/system
#
# To run with a visible browser window (debug):
#   HEADLESS=false bundle exec rspec spec/system

require "capybara/cuprite"
require "database_cleaner/active_record"

# ---------------------------------------------------------------------------
# Cuprite driver registration
# ---------------------------------------------------------------------------
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size:  [1280, 800],
    browser_options: {},
    headless: ENV.fetch("HEADLESS", "true") != "false",
    # Increase default timeout for slower CI environments.
    timeout: 10,
    js_errors: true,
    # process_timeout controls how long to wait for the browser process to start.
    process_timeout: 15
  )
end

# ---------------------------------------------------------------------------
# Capybara global config
# ---------------------------------------------------------------------------
Capybara.configure do |config|
  config.default_driver    = :rack_test        # fast, non-JS specs
  config.javascript_driver = :cuprite          # JS-capable specs
  config.default_max_wait_time = 5
  config.server = :puma, { Silent: true }
end

# ---------------------------------------------------------------------------
# RSpec configuration
# ---------------------------------------------------------------------------
RSpec.configure do |config|
  # --- DatabaseCleaner setup ------------------------------------------------

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)  # start with a clean slate
  end

  # System specs: truncation — required for cross-thread browser requests
  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
  end

  config.after(:each, type: :system) do
    DatabaseCleaner.clean
  end

  # All other spec types: transaction — fast, zero I/O, auto-rolled back
  config.before(:each) do |example|
    next if example.metadata[:type] == :system
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.after(:each) do |example|
    next if example.metadata[:type] == :system
    DatabaseCleaner.clean
  end

  # --- Cuprite + WebMock ----------------------------------------------------

  config.before(:each, type: :system) do
    driven_by :cuprite

    # Cuprite communicates with its Capybara test server and the Chrome
    # browser process over loopback TCP. WebMock blocks all real connections
    # by default, which intercepts these internal probes (/__identify__ etc.)
    # and raises NetConnectNotAllowedError before any test logic runs.
    #
    # Disable WebMock for system specs entirely — they test the full stack
    # through a real browser and do not make external HTTP calls.
    WebMock.disable!
  end

  config.after(:each, type: :system) do
    WebMock.enable!
  end
end
