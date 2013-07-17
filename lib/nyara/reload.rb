require "listen"

module Nyara
  # listen to fs events and reload code / views
  # todo add to development env: require 'nyara/reload'; Reload.listen
  module Reload
    # init, should require all files that needs to be reloaded in the given block
    def self.init
      @new_classes = []
      @trace_point = TracePoint.new :class do |tp|
        @new_classes << tp.self.to_s.to_sym
      end
      @file_list = {}
      @first_load = true
      yield
      @first_load = false
    end

    # NOTE file should end with '.rb'
    def self.load_file file
      if consts = @file_list[file]
        consts.reverse_each do |const|
          Object.send :remove_const, const
        end
      end

      @trace_point.enable
      old_consts = Object.send :constants
      if @first_load
        require file
      else
        if l = Nyara.logger
          l.info "reloading: #{file}"
        end
        begin
          load file
          @last_error = nil
        rescue Exception
          @last_error = $!
        end
      end
      @trace_point.disable
      added_consts = Object.send(:constants) - old_consts

      added_consts.concat @new_classes
      @new_classes.clear
      added_consts.uniq!
      added_consts.sort!

      @file_list[file] = added_consts
      @last_error
    end

    # start listening
    def self.listen
      views_path = Config.views_path('/')
      if views_path
        if l = Nyara.logger
          l.info "watching views change under #{views_path}"
        end
        Listen.to Config.views_path('/'), relative_paths: true do |modified, added, removed|
          modified.each do |file|
            View.on_modified file
          end
          removed.each do |file|
            View.on_removed file
          end
        end
      end

      return unless Config.development?
      if l = Nyara.logger
        l.info "watching app change under #{Config['root']}"
      end
      Listen.to Config['root'], filter: /\.rb$/, relative_paths: false do |modified, added, removed|
        (added + modified).uniq.each do |file|
          load_file file
        end
        # (1.0) todo send notification on bad files
      end
    end

    # todo (don't forget wiki doc!)
  end
end
