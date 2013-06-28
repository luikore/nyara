# patch with 2.1 methods if not defined
class String
  unless defined? b
    def b
      dup.force_encoding 'binary'
    end
  end

  unless defined? scrub
    def scrub replacement=nil, &blk
      if replacement
        replacement = replacement.encode 'UTF-16BE'
      else
        replacement = "\xFF\xFD".force_encoding 'UTF-16BE'
      end
      if blk
        r = encode("UTF-16BE", undef: :replace, invalid: :replace, fallback: blk)
      else
        r = encode("UTF-16BE", undef: :replace, invalid: :replace, replace: replacement)
      end
      r.encode("UTF-8").gsub("\0".encode("UTF-8"), '')
    end
  end
end
