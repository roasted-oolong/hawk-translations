# frozen_string_literal: true

# =============================================================================
# Rails 8.1.2 + Ruby 3.4 — ActiveRecord::Transaction#presence fix
#
# The broad presence fix for core classes is in config/application.rb.
# This initializer handles ActiveRecord::Transaction specifically, which
# is not defined until after application.rb runs.
#
# Remove when upgrading to a Rails version that fixes this.
# =============================================================================
module ActiveRecordTransactionPresenceFix
  def presence
    closed? ? nil : self
  end
end

ActiveRecord::Transaction.prepend(ActiveRecordTransactionPresenceFix)
