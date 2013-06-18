require_relative "spec_helper"

class RenderableMock
  include Nyara::Renderable

  def initialize
    @result = ''
  end
  attr_reader :result

  def send_data data
    @result << data
  end
end

module Nyara
  describe [View, Renderable] do
    before :all do
      View.init __dir__ + '/views'
    end

    before :each do
      @instance = RenderableMock.new
    end

    it "inline render with locals" do
      view = View.new nil, nil, {a: 3}, @instance, erb: '<%= a %>'
      Fiber.new{view.render}.resume
      assert_equal '3', @instance.result
    end

    it "file render" do
      view = View.new 'index', nil, {a: 3}, @instance, {}
      Fiber.new{view.render}.resume
      assert_equal '3', @instance.result
    end

    it "file render with layouts" do
      view = View.new 'index', 'layout', {a: 3}, @instance, {}
      Fiber.new{view.render}.resume
      assert_equal "<html>3</html>\n", @instance.result
    end

    context "fallback to tilt" do
      it "inline render" do
        pending
      end

      it "forbids layout in stream-friendly templates" do
        pending
      end
    end
  end
end
