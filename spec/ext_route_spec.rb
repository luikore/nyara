require_relative "spec_helper"

module Nyara
  describe Ext, "route" do
    before :each do
      Ext.clear_route
      @e1 = Route.new{
        @http_method = 'GET'
        @scope = '/hello'
        @prefix = '/hello/'
        @suffix = '(\d+)world'
        @id = :'#1'
        @conv = [:to_i]
        @controller = 'stub'
      }
      @e2 = Route.new{
        @http_method = 'GET'
        @scope = '/hello'
        @prefix = '/hello'
        @suffix = ''
        @id = :'#second'
        @conv = []
        @controller = 'stub2'
      }
      @e3 = Route.new{
        @http_method = 'GET'
        @scope = '/hello'
        @prefix = '/hello'
        @suffix = '(\d+)'
        @id = :'#third'
        @conv = [:to_i]
        @controller = 'stub3'
      }
      @e4 = Route.new{
        @http_method = 'GET'
        @scope = '/a目录'
        @prefix = '/a目录/'
        @suffix = '(\d+)-(\d+)-(\d+)'
        @id = :'#dir'
        @conv = [:to_i, :to_i, :to_i]
        @controller = 'stub4'
      }
      Ext.register_route @e1
      Ext.register_route @e2
      Ext.register_route @e3
      Ext.register_route @e4
    end

    after :all do
      Ext.clear_route
    end

    it '#register_route sub-prefix optimization' do
      rules = Ext.list_route['GET']
      assert_equal 4, rules.size

      assert_equal false, rules[0].first # first
      assert_equal true, rules[1].first  # is sub of prev
      assert_equal true, rules[2].first  # is sub of prev
      assert_equal false, rules[3].first # not sub of prev
    end

    it '#lookup_route' do
      scope, cont, args = Ext.lookup_route 'GET', '/hello', nil
      assert_equal @e2.scope, scope
      assert_equal @e2.controller, cont
      assert_equal [:'#second'], args

      scope, cont, args = Ext.lookup_route 'GET', '/hello.js', nil
      assert_equal @e2.scope, scope
      assert_equal @e2.controller, cont
      assert_equal [:'#second'], args

      scope, cont, args = Ext.lookup_route 'GET', '/hello/3world', nil
      assert_equal @e1.scope, scope
      assert_equal @e1.controller, cont
      assert_equal [:'#1', 3], args

      # same prefix as @e2, but should not be affected by @e2
      scope, cont, args = Ext.lookup_route 'GET', '/hello3', nil
      assert_equal @e3.scope, scope
      assert_equal @e3.controller, cont
      assert_equal [:'#third', 3], args

      scope, _ = Ext.lookup_route 'GET', '/world', nil
      assert_equal nil, scope

      scope, _, args = Ext.lookup_route 'GET', '/a目录/2013-6-1', nil
      assert_equal [:'#dir', 2013, 6, 1], args
    end
  end
end
