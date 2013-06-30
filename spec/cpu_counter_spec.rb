require_relative "spec_helper"

module Nyara
  describe CpuCounter do
    it "counts" do
      assert CpuCounter.count.is_a?(Integer)
    end
  end
end
