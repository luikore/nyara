require "erb"

module Nyara
  class View
    module ERB
      def self.src template
        @erb_compiler ||= begin
          c            = ::ERB::Compiler.new '<>' # trim mode
          c.pre_cmd    = ["_erbout = @_nyara_view.out"]
          c.put_cmd    = "_erbout.push"   # after newline
          c.insert_cmd = "_erbout.push"   # before newline
          c.post_cmd   = ["_erbout.join"]
          c
        end
        src, enc = @erb_compiler.compile template
        # todo do sth with enc?
        src
      end
    end
  end
end
