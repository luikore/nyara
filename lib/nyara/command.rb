module Nyara
  module Command
    extend self

    def help
      puts %Q(Usage:
  nyara new APP_NAME [options]

commands:
  nyara help\t\t\tShow this message
  nyara new APP_NAME\t\tTo initialize a new project with default template in current directory.
      options:
      -f\t\t\tForce override if same name path existed

  nyara version\t\t\tDisplay current version
      )
    end

    def version
      puts "Nyara #{Nyara::VERSION}"
    end

    def new_project(name = nil,*args)
      args ||= []
      force_create = args.include?("-f")
      require 'fileutils'
      require "erb"
      require 'ostruct'
      require_relative "view_handlers/erb"

      if name.blank?
        puts "Need project name: \n\tnyara new xxx"
        return
      end

      app_dir = File.join(Dir.pwd,name)
      templte_dir = File.join(File.dirname(__FILE__),"templates")

      FileUtils.rm_rf(app_dir) if force_create

      if Dir.exist?(app_dir)
        puts "This has same dir name's '#{name}' existed, Nyara can not override it."
        return
      end

      Dir.mkdir(app_dir)

      puts "Generate Nyara project..."
      # Copy source template
      FileUtils.cp_r(Dir.glob("#{templte_dir}/*"),app_dir)

      # render template
      files = Dir.glob("#{app_dir}/**/*")
      render_opts = {
        app_name: name
      }
      files.each do |fname|
        if not File.directory?(fname)
          render_template(fname,render_opts)
        end
      end

      puts "Enjoy!"
    end
    
    def run_server(*args)
      args ||= []
      system("bundle exec ruby config/boot.rb #{args.join(' ')}")
    end

    private
    def render_template(fname, opts = {})
      renderer = ERB.new(File.read(fname))
      locals = {
        app_name: opts[:app_name],
        nyara_version: Nyara::VERSION
      }
      File.open(fname,'w+') do |f|
        f.write renderer.result(OpenStruct.new(locals).instance_eval { binding })
      end
    end

  end
end
