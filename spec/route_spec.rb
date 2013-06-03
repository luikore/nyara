require_relative "spec_helper"

module Nyara
  describe Route do
    # fixme: ugly code
    it "#process" do
      actions1 = [
        %w[GET /hello/%f #hello_f],
        %w[POST /%s/%u-%d #post]
      ]
      preprocessed_rules = [
        ['/', 'Stub1', actions1],
        ['/hel', 'Stub2', [%w[GET / #hel]]],
        ['/ello', 'Stub3', [%w[GET /%s #ello_s]]]
      ]

      rules = Route.process preprocessed_rules
      e_prefices, e_scopes, e_ids = [
        ['POST /',      '/',     :'#post'],
        ['GET /hello/', '/',     :'#hello_f'],
        ['GET /hel',    '/hel',  :'#hel'],
        ['GET /ello/',  '/ello', :'#ello_s']
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

    it "#analyse_path" do
      r = Route.analyse_path 'GET', '/hello/%d-world%u/%s/'
      assert_equal ['GET /hello/', '%d-world%u/%s'], r

      prefix, suffix = Route.analyse_path 'GET', '/hello'
      assert_equal 'GET /hello', prefix
      assert_equal nil, suffix

      prefix, suffix = Route.analyse_path 'GET', '/'
      assert_equal 'GET /', prefix
      assert_equal nil, suffix
    end
  end
end
