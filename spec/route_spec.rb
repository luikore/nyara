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
      assert_equal "^(-?\\d+)/b$", @r.suffix
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
      re, conv = @r.compile_re '/目录/%.3da/也可以'
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

    context "#matched_lifecycle_callbacks" do
      before :each do
        @r.http_method = HTTP_METHODS['DELETE']
        @r.classes = %w[.foo .bar]
        @r.id = '#foo'
      end

      it "returns empty set when filters empty" do
        cbs = @r.matched_lifecycle_callbacks({})
        assert_equal [], cbs
      end

      it "works" do
        cbs = @r.matched_lifecycle_callbacks ':DELETE' => [:delete], '#foo' => [:foo], '.bar' => [:bar], '#baz' => [:baz]
        assert_equal [:delete, :foo, :bar], cbs
      end

      it "when classes not set" do
        @r.classes = nil
        cbs = @r.matched_lifecycle_callbacks ':DELETE' => [:delete], '#foo' => [:foo], '.bar' => [:bar], '#baz' => [:baz]
        assert_equal [:delete, :foo], cbs
      end
    end

    context ".canonicalize_callback_selector" do
      it "works" do
        s = Route.canonicalize_callback_selector '#a'
        assert_equal '#a', s
        s = Route.canonicalize_callback_selector '.b'
        assert_equal '.b', s
      end

      it "checks bad selectors" do
        assert_raise ArgumentError do
          Route.canonicalize_callback_selector ''
        end
        assert_raise ArgumentError do
          Route.canonicalize_callback_selector '*'
        end
        assert_raise ArgumentError do
          Route.canonicalize_callback_selector 'a#b'
        end
      end

      it "removes classes and pseudo classes after id" do
        s = Route.canonicalize_callback_selector "#a.b:c"
        assert_equal '#a', s
      end

      it "does not remove pseudo class after class, and upcases it" do
        s = Route.canonicalize_callback_selector ".b:c"
        assert_equal '.b:C', s
      end
    end
  end
end
