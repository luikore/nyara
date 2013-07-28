require_relative "spec_helper"
require_relative "../lib/nyara/reload"

module Nyara
  describe Reload do
    before :all do
      GC.stress = false
      @reload_root = ENV['RELOAD_ROOT'] = Dir.mktmpdir 'root'
      Dir.mkdir @reload_root + '/views'
      touch_files 'app before', 'views before'
      @server = fork do
        Dir.chdir __dir__ + '/apps' do
          exec "ruby reload.rb"
        end
      end
      sleep 2
    end

    def touch_files app_content, views_content
      File.open @reload_root + '/reloadee.rb', 'w' do |f|
        f << 'RELOADEE = ' << app_content.inspect
      end
      File.open @reload_root + '/views/index.slim', 'w' do |f|
        f << '== ' << views_content.inspect
      end
    end

    after :all do
      Process.kill :TERM, @server
      sleep 0.2
      Process.kill :KILL, @server
    end

    it "reloads" do
      GC.stress = false
      data = open 'http://localhost:3004/app', &:read
      assert_equal 'app before', data
      data = open 'http://localhost:3004/views', &:read
      assert_equal 'views before', data

      touch_files 'app after', 'views after'
      sleep 0.8

      data = open 'http://localhost:3004/views', &:read
      assert_equal 'views after', data
      data = open 'http://localhost:3004/app', &:read
      assert_equal 'app after', data
    end
  end
end
