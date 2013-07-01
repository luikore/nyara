module Nyara
  class Flash
    def initialize session
      @now = session.delete('flash.next') || ParamHash.new
      # NOTE no need to convert hash type because Session uses ParamHash for json parsing
      session['flash.next'] = @next = ParamHash.new
    end
    attr_reader :now, :next

    def [] key
      @now[key]
    end

    def []= key, value
      @next[key] = value
    end

    def clear
      @now.clear
      @next.clear
    end
  end
end
