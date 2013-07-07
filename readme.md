Not Yet Another Ruby Async web framework and server.

[![Build Status](https://travis-ci.org/luikore/nyara.png)](https://travis-ci.org/luikore/nyara)

- Faster than any web framework on rack
- Nonblock, low CPU and memory usage
- Prefork production server, mixing blocking operations is fine
- Route actions with scanf-like DSL
- Simple request format matcher with just `case ... when`
- Easy to stream the view with `Fiber.yield`

# Getting started

Requirement

- System: BSD/Linux/Mac OS X
- Interpreter: Ruby 2.0.0 or higher
- Compiler: GCC or Clang

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

# Document

- [Wiki](https://github.com/luikore/nyara/wiki/Home)
- [Manual](https://github.com/luikore/nyara/wiki/Manual)
- [API doc](http://rubydoc.info/github/luikore/nyara/master/frames)

# Participate

- [Building from source](https://github.com/luikore/nyara/wiki/Building)
- Mailing list [nyara@relist.com](mailto://nyara@relist.com)

# Caveats

- not based on [rack](https://github.com/rack/rack).
- not compatible with [eventmachine](https://github.com/eventmachine/eventmachine). It won't work if you add gems like [em-synchrony](https://github.com/igrigorik/em-synchrony).

# License

BSD 3-Clause, see [copying](https://github.com/luikore/nyara/blob/master/copying)

# Contributors

- luikore
- hooopo
