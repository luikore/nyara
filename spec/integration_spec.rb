require_relative "spec_helper"

class TestController < Nyara::Controller
  meta '#index'
  get '/' do
    content_type 'txt'
    send_string '初めまして from test'
  end

  meta '#create'
  post '/create' do
    redirect_to '#index'
  end

  put '/%z' do |name|
    send_file Nyara.config.views_path name
  end
end

class MyTest
  include Nyara::Test
end

module Nyara
  describe Nyara::Test, 'integration' do
    before :all do
      configure do
        reset
        set :env, 'test'
        map '/', TestController
        set :root, __dir__
      end
      Nyara.setup
      @test = MyTest.new
    end

    it "response" do
      @test.get "/", {'Xample' => 'résumé'}
      assert @test.response.success?
      assert_equal 'résumé', @test.request.header['Xample']
      assert_equal '初めまして from test', @test.response.body
      assert_equal 'text/plain; charset=UTF-8', @test.response.header['Content-Type']
    end

    it "redirect" do
      @test.post @test.path_to('test#create')
      assert @test.response.success?
      assert_equal 'http://localhost:3000/', @test.redirect_location
      @test.follow_redirect
      assert_equal '/', @test.request.path
    end

    it "session continuation" do
      @test.session['a'] = '3'
      @test.get "/"
      assert_equal '3', @test.session['a']
      @test.session['b'] = '4'
      @test.get "/"
      assert_equal '4', @test.session['b']
      assert_equal '3', @test.session['a']
    end

    it "send file" do
      @test.put "/layout.erb"
      data = File.read Nyara.config.views_path('layout.erb')
      assert_equal data, @test.response.body
    end
  end
end
