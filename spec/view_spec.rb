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

    def render *xs
      @instance = RenderableMock.new
      view = View.new @instance, *xs
      Fiber.new{ view.render }.resume
    end

    it "inline render with locals" do
      render nil, nil, {a: 3}, erb: '<%= a %>'
      assert_equal '3', @instance.result
    end

    it "file render" do
      render 'show', nil, {a: 3}, {}
      assert_equal '3', @instance.result
    end

    it "file render with layouts" do
      render 'show', 'layout', {a: 3}, {}
      assert_equal "<html>3</html>\n", @instance.result
    end

    it "raises for ambiguous template" do
      assert_raise ArgumentError do
        render 'edit', nil, nil, {}
      end
      render 'edit.slim', nil, nil, {}
      assert_equal "<div>slim:edit</div>", @instance.result.gsub(/\s/, '')
      render 'edit.haml', nil, nil, {}
      assert_equal "<div>haml:edit</div>", @instance.result.gsub(/\s/, '')
    end

    context "fallback to tilt" do
      it "inline render" do
        render nil, nil, {a: 3}, {liquid: '{{a}}'}
        assert_equal '3', @instance.result
      end

      it "forbids tilt layout" do
        assert_raise RuntimeError do
          render nil, 'invalid_layout', nil, {liquid: 'page'}
        end
        assert_raise RuntimeError do
          render 'show', ['invalid_layout'], nil, {}
        end
      end

      it "allows tilt page with stream-friendly layout" do
        render nil, 'layout', nil, {liquid: 'page'}
        assert_equal "<html>page</html>\n", @instance.result
      end
    end
  end
end
