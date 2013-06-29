require_relative "spec_helper"

module Nyara
  describe 'mini_support' do
    it "Array#sum" do
      assert_equal 0, [].sum
      assert_equal 3, [1, 2].sum
    end

    # just test existence, no need to repeat activesupport tests
    it "Object#blank?" do
      assert [].respond_to? :blank?
    end

    # just test existence, no need to repeat activesupport tests
    it "Object#to_query" do
      assert ''.respond_to? :to_query
    end

    it "to_json works with inheritance" do
      h = HeaderHash.new
      h[:Accept] = 'en'
      assert_equal('{"Accept":"en"}', h.to_json)
    end

    # just a class with .json_create(attrs)
    class MyClass
      def self.json_create attrs
        1
      end
    end
    it "json load security" do
      assert_equal({"json_class" => "MyClass", "length" => 1}, JSON.load('{"json_class":"MyClass","length":1}'))
    end

    it "json dump security" do
      h = {"a" => '</script>', "b" => true}
      assert_not_include(h.to_json, '</script>')
      assert_equal h, JSON.parse(h.to_json)
    end

    if RUBY_VERSION <= '2.0.0'
      it "String#b" do
        assert_equal 'ASCII-8BIT', "你".b.encoding
      end

      it "String#scrub" do
        # from rdoc examples
        assert_equal "abc\u3042\uFFFD", "abc\u3042\x81".scrub
        assert_equal "abc\u3042*", "abc\u3042\x81".scrub("*")
        assert_equal "abc\u3042<e380>", "abc\u3042\xE3\x80".scrub{|bytes| '<'+bytes.unpack('H*')[0]+'>' }
      end
    end
  end
end
