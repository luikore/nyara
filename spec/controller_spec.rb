require_relative "spec_helper"

module Nyara
  describe Controller do
    # XXX describe/context/it don't provide scopes
    # need regex search `class \w+ < Controller` to ensure no conflict in routes
    class DummyController < Controller
      set_controller_name 'pp'
      set_default_layout 'll'

      get '/' do
      end

      get '/get' do
      end
    end

    class AChildController < DummyController
    end

    it "inheritance validates name" do
      assert_raise RuntimeError do
        class NotControllerClass < Controller
        end
      end
    end

    it "inheritance of ivars" do
      assert_equal nil, AChildController.controller_name
      assert_equal 'll', AChildController.default_layout
    end

    context "generate additional routes" do
      it "GET -> HEAD" do
        routes = DummyController.nyara_compile_routes '/'
        get_paths = routes.select{|r| r.http_method_to_s == 'GET' }.map &:path
        head_paths = routes.select{|r| r.http_method_to_s == 'HEAD' }.map &:path
        assert_not_empty get_paths
        assert_equal get_paths.sort, head_paths.sort
      end

      it "index allows optional trailing slash" do
        routes = DummyController.nyara_compile_routes '/prefix'
        routes = routes.select{|r| r.http_method_to_s == 'GET' }
        slashed = routes.find{|r| r.path == '/' }
        assert slashed
        non_slashed = routes.find{|r| r.path == '' }
        assert non_slashed
      end
    end

    context "instance method argument validation" do
      it "#redirect_to checks first parameter" do
        c = DummyController.new Ext.request_new
        assert_raise ArgumentError do
          c.redirect_to '/'
        end
      end
    end
  end
end
