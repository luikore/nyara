module Nyara
  # Extended hash class for the use in configuration.
  class ConfigHash
    # @private
    alias _aref [] # :nodoc:
    # @private
    alias _aset []= # :nodoc:

    # #### Call-seq
    #
    #     config['a', 'very', 'deep', 'key']
    #
    # Equivalent to
    #
    #     config['a']['very']['deep']['key'] rescue nil
    #
    def [] *keys
      h = self
      keys.each do |key|
        if h.has_key?(key)
          if h.is_a?(ConfigHash)
            h = h._aref key
          else
            h = h[key]
          end
        else
          return nil # todo default value?
        end
      end
      h
    end

    # #### Call-seq
    #
    #     config['a', 'very', 'deep', 'key'] = value
    #
    # All intermediate level ConfigHashes are created automatically
    def []= *keys, last_key, value
      h = self
      keys.each do |key|
        if h.has_key?(key)
          if h.is_a?(ConfigHash)
            h = h._aref key
          else
            h = h[key]
          end
        else
          new_h = ConfigHash.new
          if h.is_a?(ConfigHash)
            h._aset key, new_h
          else
            h[key] = new_h
          end
          h = new_h
        end
      end
      if h.is_a?(ConfigHash)
        h._aset last_key, value
      else
        h[last_key] = value
      end
    end
  end
end
