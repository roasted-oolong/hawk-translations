# spec/support/system_spec_helper.rb
#
# Registers the Cuprite driver for system specs and configures Capybara.
#
# Driver: Cuprite (CDP-based, uses Ferrum under the hood to drive Chrome/Chromium).
# See DECISIONS.md for rationale over Playwright / Selenium.
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
# RSpec configuration for system specs
# ---------------------------------------------------------------------------
RSpec.configure do |config|
  config.before(:each, type: :system) do
    # Use Cuprite for all system specs (they all need a real browser for
    # Turbo and Stimulus to function correctly).
    driven_by :cuprite
  end
end
