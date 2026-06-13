# ActionCable::Channel::Base is a lazy Ruby autoload set up by ActionCable's
# Zeitwerk gem loader (for_gem). The autoload fires during the first web
# request when turbo/streams_channel.rb is loaded, but the nested autoload
# chain (Zeitwerk → Bootsnap → bundled_gems) fails at that point.
#
# Accessing the constant here at boot forces the autoload to resolve using
# the absolute path that Zeitwerk's __on_dir_autoloaded registers — which
# bypasses Bootsnap's load-path cache (where short-path lookups can be stale
# if actioncable was not in the load path when the cache was last written).
ActionCable::Channel::Base
