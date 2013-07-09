require_relative "spec_helper"

module Nyara
  describe Route do
    before :each do
      @r = Route.new
    end

    it "#compile prefix, suffix and conv" do
      @r.path = '/'
      @r.compile :controller_stub, '/'
      assert_equal '/', @r.prefix
      assert_equal '', @r.suffix
      assert_equal [], @r.conv

      @r.path = '/'
      @r.compile :controller_stub, '/scope'
      assert_equal '/scope', @r.prefix
      assert_equal '', @r.suffix
      assert_equal [], @r.conv

      @r.path = '/a/%d/b'
      @r.compile :controller_stub, '/scope'
      assert_equal "/scope/a/", @r.prefix
      assert_equal "^(-?[0-9]+)/b$", @r.suffix
      assert_equal [:to_i], @r.conv
    end

    it "#set_accept_exts" do
      r = Route.new
      r.set_accept_exts ['html', :js]
      assert_equal [%w"text html html", %w"application javascript js"], r.accept_mimes
      assert_equal ({'html'=>true, 'js'=>true}), r.accept_exts
    end

    it "#compile_re" do
      re, conv = @r.compile_re '%s/%u/%d/%f/%x'
      assert_equal [:to_s, :to_i, :to_i, :to_f, :hex], conv
      s = '1/2/-3/4.5/F'
      assert_equal [s, *s.split('/')], s.match(Regexp.new re).to_a

      re, conv = @r.compile_re '/'
      assert_equal '^/$', re
      assert_equal [], conv
    end

    it "#compile %z" do
      re, conv = @r.compile_re '/%z'
      assert_equal [:to_s], conv
      s = '/foo bar.baz'
      assert_equal [s, s[1..-1]], s.match(Regexp.new re).to_a
    end

    it "#compile_re with utf-8 chars" do
      re, conv = @r.compile_re '/目录/%da/也可以'
      assert_equal [:to_i], conv
      s = "/目录/12a/也可以"
      assert_equal [s, '12'], s.match(Regexp.new re).to_a
    end

    it "#analyse_path" do
      r = @r.analyse_path '/hello/%d-world%u/%s/'
      assert_equal ['/hello/', '%d-world%u/%s'], r

      prefix, suffix = @r.analyse_path '/hello'
      assert_equal '/hello', prefix
      assert_equal nil, suffix

      prefix, suffix = @r.analyse_path '/'
      assert_equal '/', prefix
      assert_equal nil, suffix
    end
  end
end
