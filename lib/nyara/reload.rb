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
      @last_error
    end
    attr_reader :last_error

    # start listening
    def listen
      @port = Config['port']
      app_path = Config['root']
      views_path = Config.views_path('/')
      if l = Nyara.logger
        l.info "watching app and view changes under #{app_path}"
        unless views_path.start_with?(app_path)
          l.warn "views not under project dir, changes not watched"
        end
      end
      @app_listener = hook_app_reload app_path
      @views_listener = hook_views_reload views_path
    end

    # stop listening
    def stop
      @app_listener.stop
      @views_listener.stop
    end

    # ---
    # child process
    # +++

    def hook_app_reload app_path
      Listen.to app_path, relative_paths: false, filter: /\.rb$/ do |modified, added, removed|
        notify 'app-modified', (added + modified).uniq
      end
    end

    def hook_views_reload views_path
      Listen.to views_path, relative_paths: true do |modified, added, removed|
        notify 'views-modified', (added + modified).uniq
        notify 'views-removed', removed
      end
    end

    def notify leader, files
      return if files.empty?
      system 'curl', "localhost:#{@port}/reload:#{leader}", '--data', files.to_query('files')
    end

    # todo (don't forget wiki doc!)
  end
end
