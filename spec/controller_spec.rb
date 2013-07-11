require_relative "spec_helper"

module Nyara
  describe Controller do
    it "inheritance validates name" do
      assert_raise RuntimeError do
        class NotControllerClass < Controller
        end
      end
    end

    it "inheritance of ivars" do
      class AParentController < Controller
        set_controller_name 'pp'
        set_default_layout 'll'
      end
      class AChildController < AParentController
      end

      assert_equal nil, AChildController.controller_name
      assert_equal 'll', AChildController.default_layout
    end
  end
end
