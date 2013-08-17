require "thor"
require "shellwords"

module Nyara
  class Command < Thor
    include Thor::Actions
    map '-v' => :version

    def self.source_root
      __dir__
    end

    desc "version", "Show version"
    def version
      puts "Nyara #{Nyara::VERSION}"
    end

    desc "new APP_NAME", "Create a project"
    def new name
      require 'fileutils'

      app_dir = File.expand_path File.join(Dir.pwd, name)
      @rel_dir = name
      @app_name = File.basename app_dir
      templte_dir = File.join(File.dirname(__FILE__), "templates")

      directory 'templates', name

      create_file app_dir + '/.gitignore' do
        %w".DS_Store config/session.key config/session_cipher.key".join "\n"
      end
      generate 'session.key'
      puts '          \\ 👻  /'
    ensure
      @app_name = nil
      @rel_dir = nil
    end

    desc "generate THING", "(PROJECT) Generate things, THING can be:
    session.key        # config/session.key
    session_cipher.key # config/session_cipher.key"
    def generate thing, app_dir=nil
      case thing
      when 'session.key'
        file = "config/session.key"
        file = File.join @rel_dir, file if @rel_dir
        create_file file do
          Session.generate_key
        end
      when 'session_cipher.key'
        file = 'config/session_cipher.key'
        file = File.join @rel_dir, file if @rel_dir
        create_file file do
          Session.generate_cipher_key
        end
      end
    end

    desc "server", "(PROJECT) Start server"
    method_option :environment, aliases: %w'-e -E', default: 'development'
    method_option :port, aliases: %w'-p -P', type: :numeric
    method_option :daemon, aliases: %w'-d -D', type: :boolean, desc: 'run server on the background'
    def server
      env = options[:environment].shellescape
      cmd = "NYARA_ENV=#{env} ruby config/boot.rb"

      if options[:port]
        cmd << " -p" << options[:port].shellescape
      end
      if options[:daemon]
        cmd << " -d"
      end
      exec cmd
    end

    desc "console", "(PROJECT) Start console"
    method_option :environment, aliases: %w'-e -E', default: 'development'
    method_option :shell, aliases: %w'-s -S', desc: "tell me which shell you want to use, pry or irb?"
    def console
      env = options[:environment].shellescape
      cmd = options[:shell]
      unless cmd
        if File.read('Gemfile') =~ /\bpry\b/
          cmd = 'pry'
        end
      end
      cmd ||= 'irb'
      if cmd != 'irb'
        cmd = "bundle exec #{cmd}"
      end
      exec "NYARA_ENV=#{env} #{cmd} -r./config/application.rb"
    end

  end
end
