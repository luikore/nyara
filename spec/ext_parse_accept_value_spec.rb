require_relative "spec_helper"

module Nyara
  describe Ext, ".parse_accept_value" do
    it 'works' do
      a = Ext.parse_accept_value ''
      assert_equal [], a

      a = Ext.parse_accept_value "text/plain; q=0.5, text/html,text/x-dvi; q=3.8, text/x-c"
      assert_equal %w[text/html text/x-dvi text/x-c text/plain], a
    end

    it "ignores q <= 0" do
      a = Ext.parse_accept_value "text/plain; q=0.0, text/html"
      assert_equal(%w'text/html', a)

      a = Ext.parse_accept_value "*, text/plain; q=-3"
      assert_equal(%w'*', a)

      a = Ext.parse_accept_value "text/plain; q=0, text/*"
      assert_equal(%w'text/*', a)
    end

    it ".parse_accept_value should be robust" do
      a = Ext.parse_accept_value 'q=0.1, text/html'
      assert_equal 'text/html', a[1]
    end
  end
end
