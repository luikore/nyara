require "listen"

module Nyara
  # listen to fs events and reload code / views
  module Reload

    extend self

    # NOTE file should end with '.rb'<br>
    # returns last error
    def load_file file
      verbose = $VERBOSE
      $VERBOSE = nil
      begin
        load file
        @last_error = nil
      rescue Exception
        @last_error = $!
      ensure
        $VERBOSE = verbose
      end
      if l = Nyara.logger
        if @last_error
          l.error @last_error
        end
      end
    end
    attr_reader :last_error

    # start listening
    def listen
      @port = Config['port']
      app_path = Config['root']
      views_path = Config.views_path('/', false)
      if l = Nyara.logger
        l.info "watching app and view changes under #{app_path}"
        unless views_path.start_with?(app_path)
          l.warn "views not under project dir, changes not watched"
        end
      end
      @app_listener = hook_app_reload app_path
      @views_listener = hook_views_reload views_path
    end

    # cleanup workers
    def stop
      if @app_listener.adapter.worker
        @app_listener.adapter.worker.stop
      end
      if @views_listener.adapter.worker
        @views_listener.adapter.worker.stop
      end
    end

    # ---
    # private
    # +++

    def hook_app_reload app_path
      l = Listen.to(app_path).relative_paths(false).filter(/\.rb$/).change do |modified, added, removed|
        notify 'app-modified', (added + modified).uniq
      end
      l.start
      l
    end

    def hook_views_reload views_path
      l = Listen.to(views_path).relative_paths(true).change do |modified, added, removed|
        notify 'views-modified', (added + modified).uniq
        notify 'views-removed', removed
      end
      l.start
      l
    end

    def notify leader, files
      return if files.empty?
      data = files.to_query('files')
      s = TCPSocket.new 'localhost', @port
      s << "POST /reload:#{leader}\r\nContent-Length: #{data.bytesize}\r\n\r\n" << data
      s.close
    end
  end
end
