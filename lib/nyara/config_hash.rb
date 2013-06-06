module Nyara
  class ConfigHash
    alias aset []=

    # so you can write:
    # config['a', 'very', 'deep', 'key'] = 'value
    def []= *keys, last_key, value
      h = self
      keys.each_with_index do |key, i|
        if h.has_key?(key)
          h = h[key]
        elsif h.is_a?(ConfigHash)
          new_h = ConfigHash.new
          h.aset key, new_h
          h = new_h
        else
          raise "self#{keys[0...i].inspect} is not a ConfigHash"
        end
      end
      h.aset last_key, value
    end
  end
end
