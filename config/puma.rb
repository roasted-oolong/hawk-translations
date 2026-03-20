# Puma configuration for Hawk Translations
#
# Single worker mode intentional — 1GB RAM constraint on Oracle AMD E2 micro.
# Revisit WEB_CONCURRENCY when migrating to Ampere A1 (24GB RAM).

threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

plugin :tmp_restart

# Run Solid Queue supervisor inside Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Suppress warning about running cluster mode with 1 worker — intentional.
silence_single_worker_warning
