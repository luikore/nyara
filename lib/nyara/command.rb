module Nyara
  module Command
    extend self
    
    def help
      puts %Q(Usage:
  nyara new APP_NAME [options]

commands:
  nyara help\t\t\tShow this message
  nyara new APP_NAME\t\tTo initialize a new project with default template in current directory.
  nyara version\t\t\tDisplay current version
      )
    end
    
    def version
      puts "Nyara #{Nyara::VERSION}"
    end
    
    def new_project(name = nil)
      require 'fileutils'
      require "erb"
      require 'ostruct'
      require_relative "view_handlers/erb"
      
      if name.blank?
        puts "Need project name: \n\tnyara new xxx"
        return
      end
      
      app_dir = File.join(Dir.pwd,name)
      FileUtils.rm_rf(app_dir) # TODO: will remove it
      if Dir.exist?(app_dir)
        puts "This has same dir name's '#{name}' existed, Nyara can not override it."
        return
      end
      
      Dir.mkdir(app_dir)
      
      puts "Generate Nyara project..."
      # Copy source template
      FileUtils.cp_r(Dir.glob('lib/nyara/templates/*'),app_dir)
      
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