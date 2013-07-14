require "listen"

module Nyara
  # listen to fs events and reload code / views
  # todo add to development env: require 'nyara/reload'; Reload.listen
  module Reload
    def self.listen
      Listen.to Config.views_path('/'), relative_paths: true do |modified, added, removed|
        modified.each do |file|
          View.on_modified file
        end
        removed.each do |file|
          View.on_removed file
        end
      end

      return unless Config['reload_paths']
      Listen.to Config.root, filter: Config['reload_paths'] do |modified, added, removed|
        removed.each do
          reload_all
          return
        end

        changed = false

        added.each do |file|
          if file.end_with?('.rb')
            begin
              require file
            rescue Exception
              puts $!
              puts $!.backtrace
            end
            changed = true
          end
        end

        modified.each do |file|
          if file.end_with?('.rb')
            begin
              reload file
            rescue Exception
              puts $!
              puts $!.backtrace
            end
            changed = true
          end
        end

        if changed
          Nyara.setup
          # todo after-reload hook
        end
        # (1.0) todo send notification on bad files
      end
    end

    # todo (don't forget wiki doc!)

    def self.reload_all

    end
  end
end
