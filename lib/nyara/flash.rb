module Nyara
  class Flash
    def initialize session
      @now = ParamHash.new
      @next = (session['flash'] ||= ParamHash.new)
    end
    attr_reader :now, :next

    def [] key
      @now.delete(key) || @next.delete(key)
    end

    def []= key, value
      @next[key] = value
    end
  end
end
