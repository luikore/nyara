Not Yet Another Ruby Async web framework and server.

[![Build Status](https://travis-ci.org/luikore/nyara.png)](https://travis-ci.org/luikore/nyara)

- Fast
- Evented IO while API remains synchrony
- Prefork production server, mixing a bit blocking operations won't block other users
- Sinatra-like http method and scanf-like http path and path helper
- Request format matcher with just `case ... when`
- Easy to stream the view with `Fiber.yield`

# Getting started

Requirement

- BSD/Linux/Mac OS X
- Ruby 2.0.0 or higher
- GCC or Clang

Install

```bash
gem ins --pre nyara
```

Edit a file, name it `nyahaha.rb` for example

```ruby
require 'nyara'
get '/' do
  send_string 'hello world'
end
```

And start server

```bash
ruby nyahaha.rb
```

# Documentation

- [Wiki](https://github.com/luikore/nyara/wiki/Home)
- [Manual](https://github.com/luikore/nyara/wiki/Manual)
- [API doc](http://rubydoc.info/github/luikore/nyara/master/frames)
- [Building from source](https://github.com/luikore/nyara/wiki/Building)

# Caveats

- *Nyara* is not based on [rack](https://github.com/rack/rack).
- *Nyara* is not compatible with [eventmachine](https://github.com/eventmachine/eventmachine). It won't work if you add gems like [em-synchrony](https://github.com/igrigorik/em-synchrony).

# License

BSD 3-Clause, see [copying](https://github.com/luikore/nyara/blob/master/copying)

# Contributors

luikore
hooopo
