configure do
  set :port, 3000          # set listening port number
  set :workers, 4          # set number of worker process
                           # if not set, will estimate best n by CPU count

  set :logger, true        # equivalent to no setting
end
