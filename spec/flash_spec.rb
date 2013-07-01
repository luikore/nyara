require_relative "spec_helper"

module Nyara
  describe Flash do
    before :each do
      @session = ParamHash.new
      @flash = Flash.new @session
    end

    it "#next" do
      @flash[:foo] = 'foo'
      assert_equal 'foo', @flash.next['foo']
      assert_not_empty @session.values.first

      @flash.next[:bar] = 'bar'
      assert_equal 'bar', @flash['bar']
    end

    it "#now" do
      @flash.now['foo'] = 'foo'
      assert_nil @flash.next['foo']
      assert_empty @session.values.first

      @flash.next['foo'] = 'bar'
      assert_equal 'foo', @flash['foo']
      assert_equal 'bar', @flash['foo']
    end
  end
end
