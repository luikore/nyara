require_relative "spec_helper"

class TestController < Nyara::Controller
  meta '#index'
  get '/' do
    content_type 'txt'
    send_string 'hello from test'
  end

  meta '#create'
  post '/create' do
    redirect_to '#index'
  end
end

class MyTest
  include Nyara::Test
end

module Nyara
  describe Nyara::Test do
    before :all do
      configure do
        reset
        set :env, 'test'
        map '/', TestController
      end
      Nyara.setup
      @test = MyTest.new
    end

    it "response" do
      @test.get "/"
      assert @test.response.success?
      assert_equal 'hello from test', @test.response.body
      assert_equal 'text/plain; charset=UTF-8', @test.response.header['Content-Type']
    end

    it "redirect" do
      @test.post @test.path_to('test#create')
      assert @test.response.success?
      assert_equal 'http://localhost/', @test.redirect_location
      @test.follow_redirect
      assert_equal '/', @test.request.path
    end
  end
end
