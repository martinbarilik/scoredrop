# Starts the background poller thread inside the web process only
# (`bin/rails server`). Set POLLER_ENABLED=false to disable.
Rails.application.config.after_initialize do
  if defined?(Rails::Server) && ENV.fetch("POLLER_ENABLED", "true") == "true"
    Thread.new do
      Thread.current.name = "poller"
      Poller.run!
    end
  end
end
