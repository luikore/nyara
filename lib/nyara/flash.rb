module Nyara
  # convenient thingy that let you can pass instant message to next request<br>
  # it is consumed as soon as next request arrives
  class Flash
    def initialize session
      # NOTE no need to convert hash type because Session uses ParamHash for json parsing
      @now = session.delete('flash.next') || ParamHash.new
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
