require_relative "spec_helper"

module Nyara
  describe 'evented IO' do
    before :all do
      pid = Process.pid
      @server = fork do
        exec 'ruby', __dir__ + '/apps/connect.rb'
      end
      GC.stress = false
      sleep 1.8 # wait for server startup
    end

    after :all do
      Process.kill :KILL, @server
    end

    it "works" do
      GC.stress = false # open-uri creates too many objects!
      result1 = open "http://localhost:3003", &:read
      result2 = open "http://baidu.com", &:read
      assert_equal result2, result1
    end
  end
end
