require_relative "spec_helper"

module Nyara
  describe Ext, "route" do
    before :each do
      Ext.clear_route
      @e1 = RouteEntry.new{
        @http_method = 'GET'
        @scope = '/hello'
        @prefix = '/hello/'
        @suffix = '(\d+)world'
        @id = :'#1'
        @conv = [:to_i]
        @controller = 'stub'
      }
      @e2 = RouteEntry.new{
        @http_method = 'GET'
        @scope = '/hello'
        @prefix = '/hello'
        @suffix = ''
        @id = :'#second'
        @conv = []
        @controller = 'stub2'
      }
      @e3 = RouteEntry.new{
        @http_method = 'GET'
        @scope = '/a目录'
        @prefix = '/a目录/'
        @suffix = '(\d+)-(\d+)-(\d+)'
        @id = :'#dir'
        @conv = [:to_i, :to_i, :to_i]
        @controller = 'stub3'
      }
      Ext.register_route @e1
      Ext.register_route @e2
      Ext.register_route @e3
    end

    after :all do
      Ext.clear_route
    end

    it '#register_route sub-prefix optimization' do
      rules = Ext.list_route['GET']
      assert_equal 3, rules.size

      assert_equal false, rules[0].first # first
      assert_equal true, rules[1].first  # is sub of prev
      assert_equal false, rules[2].first # not sub of prev
    end

    it '#lookup_route' do
      scope, cont, args = Ext.lookup_route 'GET', '/hello'
      assert_equal @e2.scope, scope
      assert_equal @e2.controller, cont
      assert_equal [:'#second'], args

      scope, cont, args = Ext.lookup_route 'GET', '/hello/3world'
      assert_equal @e1.scope, scope
      assert_equal @e1.controller, cont
      assert_equal [3, :'#1'], args

      scope, _ = Ext.lookup_route 'GET', '/world'
      assert_equal nil, scope

      scope, _, args = Ext.lookup_route 'GET', '/a目录/2013-6-1'
      assert_equal [:'#dir', 2013, 6, 1], args
    end
  end
end
