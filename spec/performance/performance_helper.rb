require_relative "../../lib/nyara/nyara"

def dump data
  in_spec = ENV['NYARA_FORKED'] == 'spec'
  GC.start
  GC.disable
  if in_spec
    print Marshal.dump data
  else
    p data
  end
end
