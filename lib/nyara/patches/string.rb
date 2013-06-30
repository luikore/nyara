# patch with 2.1 methods if not defined
class String
  unless defined? b
    def b
      dup.force_encoding 'binary'
    end
  end

  unless defined? scrub
    # NOTE: block unsupported
    def scrub replacement=nil
      if replacement
        replacement = replacement.encode 'UTF-16BE'
      else
        replacement = "\xFF\xFD".force_encoding 'UTF-16BE'
      end
      r = encode("UTF-16BE", undef: :replace, invalid: :replace, replace: replacement)
      r.encode("UTF-8").gsub("\0".encode("UTF-8"), '')
    end
  end
end
