require "thor"
require "shellwords"

module Nyara
  class Command < Thor
    desc "version", "Show version"
    def version
      puts "Nyara #{Nyara::VERSION}"
    end

    desc "new APP_NAME", "Create a project"
    method_option :force, aliases: '-f', desc: 'Force override old', type: :boolean, default: false
    def new name
      require 'fileutils'
      require "erb"
      require 'ostruct'
      require_relative "view_handlers/erb"

      app_dir = File.join(Dir.pwd, name)
      templte_dir = File.join(File.dirname(__FILE__), "templates")

      FileUtils.rm_rf(app_dir) if options[:force]

      if Dir.exist?(app_dir)
        puts "This has same dir name's '#{name}' existed, Nyara can not override it."
        return
      end

      Dir.mkdir(app_dir)

      puts "Generate Nyara project..."
      source_templates = Dir.glob("#{templte_dir}/*")
      puts source_templates.map{|f| File.basename f }
      FileUtils.cp_r(source_templates, app_dir)

      # render template
      files = Dir.glob("#{app_dir}/**/*")
      render_opts = {
        app_name: name
      }
      files.each do |fname|
        if not File.directory?(fname)
          render_template(fname, render_opts)
        end
      end

      Dir.chdir app_dir do
        generate 'session.key'
        puts ".gitignore"
        File.open '.gitignore', 'w' do |f|
          f.puts ".DS_Store"
          f.puts "config/session.key"
          f.puts "config/session_cipher.key"
        end
      end
      puts "Enjoy!"
    end

    desc "generate THING", "(PROJECT) Generate things, THING can be:
    session.key        # config/session.key
    session_cipher.key # config/session_cipher.key"
    def generate thing
      case thing
      when 'session.key'
        puts "config/session.key"
        File.open 'config/session.key', 'wb' do |f|
          f << Session.generate_key
        end
      when 'session_cipher.key'
        puts "config/session_cipher.key"
        File.open 'config/session_cipher.key', 'wb' do |f|
          f << Session.generate_cipher_key
        end
      end
    end

    desc "server", "(PROJECT) Start server"
    method_option :environment, aliases: %w'-e -E', default: 'development'
    def server
      env = options[:environment].shellescape
      exec "NYARA_ENV=#{env} ruby config/boot.rb"
    end

    desc "console", "(PROJECT) Start console"
    method_option :environment, aliases: %w'-e -E', default: 'development'
    method_option :shell, aliases: '-s', desc: "tell me which shell you want to use, pry or irb?"
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

    private
    def render_template(fname, opts = {})
      renderer = ERB.new(File.read(fname))
      locals = {
        app_name: opts[:app_name],
        nyara_version: Nyara::VERSION
      }
      File.open(fname, 'w+') do |f|
        f.write renderer.result(OpenStruct.new(locals).instance_eval { binding })
      end
    end

  end
end
