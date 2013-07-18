require_relative "spec_helper"
require 'logger'

class TestController < Nyara::Controller
  attr_reader :before_invoked

  before ":delete" do
    @before_invoked = true
  end

  meta '#index'
  get '/' do
    content_type 'txt'
    send_string '初めまして from test'
  end

  meta '#create'
  post '/create' do
    set_header 'partial', partial('_partial').strip
    redirect_to '#index'
  end

  post '/upload' do
    params
    # no response
  end

  put '/send_file/%z' do |name|
    send_file Nyara.config.views_path name
  end

  delete '/render' do
    render 'edit.slim'
  end

  patch '/stream' do
    view = stream 'edit.slim'
    view.resume
    view.end
  end

  http :trace, '/stream-with-partial' do
    view = stream erb: "before:<%= partial '_partial_with_yield' %>:after"
    view.resume
    view.end
  end

  options '/error' do
    raise 'error'
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
        map '/', TestController
        set :root, __dir__
        set :public, 'public'
        set :logger, false
      end
      Nyara.setup
      @test = MyTest.new
    end

    before :each do
      GC.stress = false
    end

    it "decodes cookie" do
      @test.get "/", {"Cookie" => 'foo=bar'}
      assert_equal 'bar', @test.env.cookie['foo']
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
      assert_equal 'This is a partial', @test.response.header['Partial']
      assert @test.response.success?
      assert_equal 'http://localhost:3000/', @test.redirect_location
      @test.follow_redirect
      assert_equal '/', @test.request.path
    end
    
    it "post params log output" do
      data = { name: 1, sex: 0 }
      Nyara.config.stub(:logger).and_return(Logger.new($stdout))
      out = capture(:stdout) { @test.post @test.path_to('test#create'), {}, data }
      # puts out
      assert_include out, 'params: {"name"=>"1", "sex"=>"0"}'
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

    it "send_file" do
      @test.put "/send_file/layout.erb"
      data = File.read Nyara.config.views_path('layout.erb')
      assert_equal data, @test.response.body
    end

    it "render" do
      @test.delete "/render"
      assert_include @test.response.body, "slim:edit"
    end

    it "stream" do
      @test.patch '/stream'
      assert_include @test.response.body, "slim:edit"
    end

    it "stream-with-yield" do
      @test.http :trace, '/stream-with-partial'
      assert @test.response.success?
      assert_equal "before:yield:after", @test.response.body.strip
    end

    it "error" do
      @test.options '/error'
      assert_equal 500, @test.response.status
      assert_equal false, @test.response.success?
    end

    it "multipart upload" do
      data = File.binread(__dir__ + '/raw_requests/multipart')
      @test.env.process_request_data data
      param = @test.env.request.param
      assert_equal 'foo', param['foo']
      assert_equal 'bar', param['bar']['data']
      assert_equal 'baz', param['baz']['你好']['data']
    end

    context "public static content" do
      it "found file" do
        @test.get "/index.html"
        assert_equal 200, @test.response.status
        assert_equal "index.html", @test.response.body
      end

      it "found empty file" do
        @test.get "/empty file.html"
        assert_equal 200, @test.response.status
        assert_empty @test.response.body
      end

      it "missing file" do
        @test.get "/missing.html"
        assert_equal 404, @test.response.status
      end

      it "found but directory" do
        @test.get "/empty"
        assert_equal 404, @test.response.status
      end
      
      it "found test.css and text/css content_type" do
        @test.get "/test.css"
        assert_equal "test css", @test.response.body
        assert_include @test.response.header['Content-Type'],"text/css"
      end
      
      it "found test.js" do
        @test.get "/test.js"
        assert_equal "test js", @test.response.body
        assert_include @test.response.header['Content-Type'],"application/javascript"
      end
      
      it "found test.jpg" do
        @test.get "/test.jpg"
        assert_include @test.response.header['Content-Type'],"image/jpeg"
      end
    end

    context "before / after" do
      it "invokes lifecycle callback" do
        @test.get '/'
        assert_nil @test.env.controller.before_invoked
        assert @test.request.message_complete?

        @test.delete "/render"
        assert @test.env.controller.before_invoked
      end
    end
  end
end
