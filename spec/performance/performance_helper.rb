require_relative "../../lib/nyara/nyara"

# baseline is the raw loop
def bench n
  t = Time.now
  n.times{ yield }
  cost = Time.now - t

  t = Time.now
  n.times{}
  baseline = Time.now - t

  cost - baseline
end

# custom baseline
def bench_raw n
  t = Time.now
  n.times{ yield }
  Time.now - t
end
