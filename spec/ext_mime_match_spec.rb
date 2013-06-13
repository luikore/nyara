require_relative "spec_helper"

module Nyara
  describe Ext, '.mime_match' do
    it "#mime_match_seg" do
      a = Ext.mime_match_seg 'text', 'text', 'html'
      assert_equal true, a

      a = Ext.mime_match_seg 'text/html', 'text', 'stylesheet'
      assert_equal false, a

      a = Ext.mime_match_seg '*', 'text', 'html'
      assert_equal true, a
    end

    it "#mime_match works with wildcards" do
      a = Ext.mime_match '*', [%w'text html html']
      assert_equal 'html', a

      a = Ext.mime_match 'text/*', [%w'some text txt', %w'text html html']
      assert_equal 'html', a

      a = Ext.mime_match 'text/*', [%w'some text txt']
      assert_nil a
    end

    it "#mime_match ignores encodings" do
      accept = 'application/javascript ; charset=UTF-8, text/*'

      a = Ext.mime_match accept, [%w'application javascript js']
      assert_equal 'js', a

      a = Ext.mime_match accept, [%w'text javascript js']
      assert_equal 'js', a

      a = Ext.mime_match accept, [['javascript', '', 'js']]
      assert_nil a
    end
  end
end
