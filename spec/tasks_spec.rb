require "rake"
require 'rake/testtask'
require_relative "spec_helper"
require_relative "../lib/nyara/tasks"

module Nyara
  describe "tasks" do
    describe "routes" do
      it "should work" do
        out = stdout { Rake.application['routes'].invoke }
        assert_include(out, "all routes:")
      end
    end
  end
end