require_relative "spec_helper"

class FooController < Nyara::Controller
  meta '#index'
  get '/%d' do |id|
  end

  class BarController < Nyara::Controller
    meta '#index'
    get '/' do
    end
  end

  class BazController < Nyara::Controller
    set_name 'baz'

    meta '#index'
    get '/%d' do |id|
    end
  end
end

module Nyara
  describe [Controller, Route] do
    before :all do
      Route.clear
      Config.configure do
        set 'host', 'yavaeye.com'
        map '/', 'foo'
        map '/bar-prefix', 'foo_controller::bar'
        map '/baz-prefix', 'foo_controller::baz'
      end
      Route.compile
    end

    context '#path_for' do
      it "local query" do
        c = FooController.new :stub_request
        assert_equal '/12', c.path_for('#index', 12)
        assert_raise ArgumentError do
          c.path_for '#index'
        end
        assert_raise ArgumentError do
          c.path_for('#index', 'a')
        end
      end

      it "global query" do
        c = FooController::BarController.new :stub_request
        assert_equal '/bar-prefix/', c.path_for('foo_controller::bar#index')
        assert_equal '/baz-prefix/1', c.path_for('baz#index', 1)
      end

      it "generates for nested query" do
        pending
      end

      it "perserves _method query" do
        pending
      end

      it "appends format and query" do
        c = FooController.new :stub_request
        generated = c.path_for '#index', 1, format: 'js', 'utm_source' => 'a spam'
        assert_equal "/1.js?utm_source=a+spam", generated
      end
    end

    context '#url_for' do
      it "works" do
        c = FooController::BazController.new :stub_request
        assert_equal '//yavaeye.com/baz-prefix/1', c.url_for('#index', 1)
        assert_equal 'https://localhost:4567/1', c.url_for('foo#index', 1, scheme: 'https', host: 'localhost:4567')
      end
    end
  end
end
