require "haml"

module Nyara
  class View
    module Haml
      def self.src template
        e = ::Haml::Engine.new template
        # todo trim mode
        <<-RUBY
_hamlout = ::Haml::Buffer.new(nil, encoding: 'utf-8'); _hamlout.buffer = @_nyara_view.out
#{e.precompiled}
_hamlout.buffer.join
RUBY
      end
    end
  end
end
