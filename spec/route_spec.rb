require_relative "spec_helper"

module Nyara
  describe Route do
    # fixme: ugly code
    it "#process" do
      entries1 = [
        RouteEntry.new{
          @http_method = 'GET',
          @path = '/hello/%f',
          @id = :'#hello_f'
        },
        RouteEntry.new{
          @http_method = 'POST',
          @path = '/%s/%u-%d',
          @id = :'#post'
        }
      ]
      entries2 = [
        RouteEntry.new{
          @http_method = 'GET',
          @path = '/',
          @id = :'#hel'
        }
      ]
      entries3 = [
        RouteEntry.new{
          @http_method = 'GET',
          @path = '/%s',
          @id = :'#ello_s'
        }
      ]

      preprocessed_rules = [
        ['/', 'Stub1', entries1],
        ['/hel', 'Stub2', entries2],
        ['/ello', 'Stub3', entries3]
      ]

      rules = Route.process preprocessed_rules
      e_prefices, e_scopes, e_ids = [
        ['/hello/', '/',     :'#hello_f'],
        ['/hel',    '/hel',  :'#hel'],
        ['/ello/',  '/ello', :'#ello_s'],
        ['/',       '/',     :'#post']
      ].transpose

      assert_equal e_prefices, rules.map(&:prefix)
      assert_equal e_scopes, rules.map(&:scope)
      assert_equal e_ids, rules.map(&:id)
    end

    it "#compile_re" do
      re, conv = Route.compile_re '%s/%u/%d/%f/%x'
      assert_equal [:to_s, :to_i, :to_i, :to_f, :hex], conv
      s = '1/2/-3/4.5/F'
      assert_equal [s, *s.split('/')], s.match(Regexp.new re).to_a

      re, conv = Route.compile_re '/'
      assert_equal '^/$', re
      assert_equal [], conv
    end

    it "#compile_re with utf-8 chars" do
      re, conv = Route.compile_re '/目录/%da/也可以'
      assert_equal [:to_i], conv
      s = "/目录/12a/也可以"
      assert_equal [s, '12'], s.match(Regexp.new re).to_a
    end

    it "#analyse_path" do
      r = Route.analyse_path '/hello/%d-world%u/%s/'
      assert_equal ['/hello/', '%d-world%u/%s'], r

      prefix, suffix = Route.analyse_path '/hello'
      assert_equal '/hello', prefix
      assert_equal nil, suffix

      prefix, suffix = Route.analyse_path '/'
      assert_equal '/', prefix
      assert_equal nil, suffix
    end
  end
end
