# patch core classes first
require_relative "patches/mini_support"

# master require
require "fiber"
require "cgi"
require "uri"
require "openssl"
require "socket"
require "tilt"
require "time"

require_relative "../../ext/nyara"
require_relative "hashes/param_hash"
require_relative "hashes/header_hash"
require_relative "hashes/config_hash"
require_relative "mime_types"
require_relative "controller"
require_relative "request"
require_relative "cookie"
require_relative "session"
require_relative "flash"
require_relative "config"
require_relative "route"
require_relative "view"
require_relative "cpu_counter"
require_relative "part"

# default controllers
require_relative "controllers/public_controller"

module Nyara
  HTTP_STATUS_FIRST_LINES = Hash[HTTP_STATUS_CODES.map{|k,v|[k, "HTTP/1.1 #{k} #{v}\r\n".freeze]}].freeze

  HTTP_REDIRECT_STATUS = [300, 301, 302, 303, 307]

  # Base header response for 200<br>
  # Caveat: these entries can not be deleted
  OK_RESP_HEADER = HeaderHash.new
  OK_RESP_HEADER['Content-Type'] = 'text/html; charset=UTF-8'
  OK_RESP_HEADER['Cache-Control'] = 'no-cache'
  OK_RESP_HEADER['Transfer-Encoding'] = 'chunked'
  OK_RESP_HEADER['X-XSS-Protection'] = '1; mode=block'
  OK_RESP_HEADER['X-Content-Type-Options'] = 'nosniff'
  OK_RESP_HEADER['X-Frame-Options'] = 'SAMEORIGIN'

  START_CTX = {
    0 => $0.dup,
    argv: ARGV.map(&:dup),
    cwd: (begin
      a = File.stat(pwd = ENV['PWD'])
      b = File.stat(Dir.pwd)
      a.ino == b.ino && a.dev == b.dev ? pwd : Dir.pwd
    rescue
      Dir.pwd
    end)
  }

  class << self
    def config
      raise ArgumentError, 'block not accepted, did you mean Nyara::Config.config?' if block_given?
      Config
    end

    def setup
      Session.init
      Config.init
      Route.compile
      # todo lint if SomeController#request, send_header are re-defined
      View.init
    end

    def start_server
      port = Config[:port]

      puts "starting #{Config[:env]} server at 0.0.0.0:#{port}"
      case Config[:env].to_s
      when 'production'
        patch_tcp_socket
        start_production_server port
      when 'test'
        # don't
      else
        patch_tcp_socket
        start_development_server port
      end
    end

    def patch_tcp_socket
      puts "patching TCPSocket"
      require_relative "patches/tcp_socket"
    end

    def start_development_server port
      trap :INT do
        exit!
      end

      t = Thread.new do
        server = TCPServer.new '0.0.0.0', port
        server.listen 1000
        Ext.init_queue
        Ext.run_queue server.fileno
      end
      t.join
    end

    # Signals:
    #
    # * `INT`   - kill -9 all workers, and exit
    # * `QUIT`  - graceful quit all workers, and exit if all children terminated
    # * `TERM`  - same as QUIT
    # * `USR1`  - restore worker number
    # * `USR2`  - graceful spawn a new master and workers, with all content respawned
    # * `TTIN`  - increase worker number
    # * `TTOUT` - decrease worker number
    #
    # To make a graceful hot-restart:
    #
    # 1. USR2 -> old master
    # 2. if good (workers are up, etc), QUIT -> old master, else QUIT -> new master and fail
    # 3. if good (requests are working, etc), INT -> old master
    #    else QUIT -> new master and USR1 -> old master to restore workers
    #
    # * NOTE in step 2/3 if an additional fork executed in new master and hangs,<br>
    #   you may need send an additional INT to terminate it.
    # * NOTE hot-restart reloads almost everything, including Gemfile changes and configures except port.<br>
    #   but, if some critical environment variable or port configure needs change, you still need cold-restart.
    # * TODO write to a file to show workers are good
    # * TODO detect port config change
    def start_production_server port
      workers = Config[:workers]

      puts "workers: #{workers}"

      if (server_fd = ENV['NYARA_FD'].to_i) > 0
        puts "inheriting server fd #{server_fd}"
        @server = TCPServer.for_fd server_fd
      end
      unless @server
        @server = TCPServer.new '0.0.0.0', port
        @server.listen 1000
        ENV['NYARA_FD'] = @server.fileno.to_s
      end

      GC.start
      @workers = []
      workers.times do
        incr_workers nil
      end

      trap :INT,  &method(:kill_all)
      trap :QUIT, &method(:quit_all)
      trap :TERM, &method(:quit_all)
      trap :USR2, &method(:spawn_new_master)
      trap :USR1, &method(:restore_workers)
      trap :TTIN do
        if Config[:workers] > 1
          Config[:workers] -= 1
          decr_workers nil
        end
      end
      trap :TTOU do
        Config[:workers] += 1
        incr_workers nil
      end
      Process.waitall
    end

    private

    # Kill all workers and exit
    def kill_all sig
      @workers.each do |w|
        Process.kill :KILL, w
      end
      exit!
    end

    # Graceful quit all workers and exit
    def quit_all sig
      until @workers.empty?
        decr_workers sig
      end
      # wait will finish the wait-and-quit job
    end

    # Spawn a new master
    def spawn_new_master sig
      fork do
        @server.close_on_exec = false
        Dir.chdir START_CTX[:cwd]
        if File.executable?(START_CTX[0])
          exec START_CTX[0], *START_CTX[:argv], close_others: false
        else
          # gemset env should be correct because env is inherited
          require "rbconfig"
          ruby = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])
          exec ruby, START_CTX[0], *START_CTX[:argv], close_others: false
        end
      end
    end

    # Restore number of workers as Config
    def restore_workers sig
      (Config[:workers] - @workers.size).times do
        incr_workers sig
      end
    end

    # Graceful decrease worker number by 1
    def decr_workers sig
      w = @workers.shift
      puts "killing worker #{w}"
      Process.kill :QUIT, w
    end

    # Increase worker number by 1
    def incr_workers sig
      pid = fork {
        $0 = "(nyara:worker) ruby #{$0}"

        trap :QUIT do
          Ext.graceful_quit @server.fileno
        end

        trap :TERM do
          Ext.graceful_quit @server.fileno
        end

        t = Thread.new do
          Ext.init_queue
          Ext.run_queue @server.fileno
        end
        t.join
      }
      @workers << pid
    end
  end
end
