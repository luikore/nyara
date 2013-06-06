module Nyara
  class ConfigHash
    alias aref []
    alias aset []=

    # so you can find with chained keys
    def [] *keys
      h = self
      keys.each do |key|
        if h.has_key?(key)
          if h.is_a?(ConfigHash)
            h = h.aref key
          else
            h = h[key]
          end
        else
          return nil # todo default value?
        end
      end
      h
    end

    # so you can write:
    # config['a', 'very', 'deep', 'key'] = 'value
    def []= *keys, last_key, value
      h = self
      keys.each do |key|
        if h.has_key?(key)
          if h.is_a?(ConfigHash)
            h = h.aref key
          else
            h = h[key]
          end
        else
          new_h = ConfigHash.new
          if h.is_a?(ConfigHash)
            h.aset key, new_h
          else
            h[key] = new_h
          end
          h = new_h
        end
      end
      h.aset last_key, value
    end
  end
end
