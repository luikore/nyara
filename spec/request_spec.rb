require_relative "spec_helper"

module Nyara
  describe [Request, Controller] do
    before :each do
      Request.clear_route
      @e1 = RouteEntry.new{
        @scope = '/hello'
        @prefix = '/hello/'
        @suffix = '(\d+)world'
        @id = :'#1'
        @conv = [:to_i]
        @controller = 'stub'
      }
      @e2 = RouteEntry.new{
        @scope = '/hello'
        @prefix = '/hello'
        @suffix = ''
        @id = :'#second'
        @conv = []
        @controller = 'stub2'
      }
      Request.register_route @e1
      Request.register_route @e2
    end

    after :all do
      Request.clear_route
    end

    it '#register_route' do
      rules = Request.inspect_route
      assert_equal 2, rules.size

      scope, prefix, is_sub = rules[0]
      assert_equal false, is_sub
      scope, prefix, is_sub = rules[1]
      assert_equal true, is_sub
    end

    it '#search_route' do
      scope, cont, args = Request.search_route '/hello'
      assert_equal @e2.scope, scope
      assert_equal @e2.controller, cont
      assert_equal [], args

      scope, cont, args = Request.search_route '/hello/3world'
      assert_equal @e1.scope, scope
      assert_equal @e1.controller, cont
      assert_equal [3], args

      assert_equal nil, (Request.search_route '/world').first
    end
  end
end
