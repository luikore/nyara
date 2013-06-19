require_relative "spec_helper"

module Nyara
  describe Ext do
    it ".parse_accept_value" do
      h = Ext.parse_accept_value "text/plain; q=0.5, text/html,text/x-dvi; q=3.8, text/x-c"
      assert_equal({'text/plain'=>0.5, 'text/html'=>1, 'text/x-dvi'=>1,'text/x-c'=>1}, h)

      h = Ext.parse_accept_value ''
      assert_equal({}, h)
    end

    it ".parse_accept_value should be robust" do
      h = Ext.parse_accept_value 'q=0.1, text/html'
      assert_equal 1, h['text/html']
    end
  end
end
