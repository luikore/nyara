require_relative "spec_helper"

module Nyara
  describe RouteEntry do
    it "#set_accept_exts" do
      r = RouteEntry.new
      r.set_accept_exts ['html', :js]
      assert_equal [%w"text html html", %w"application javascript js"], r.accept_mimes
      assert_equal ({'html'=>true, 'js'=>true}), r.accept_exts
    end
  end
end