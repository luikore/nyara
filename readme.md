# NOTE

This repo is obsolete. The main point of event based IO is less memory for concurrent connections, and pay less time in CPU context switching, thus leading to higher performance benchmarks. But in real the heavy computation remains in ORMs like active record, the saved CPU time is insignificant while the implementation requires complex tweaks.

---

ニャラ is **Not Yet Another Ruby Async** web framework and server.

[![Build Status](https://travis-ci.org/luikore/nyara.png)](https://travis-ci.org/luikore/nyara)

- Very few runtime dependencies, faster than any web framework on rack.
- Nonblock but no callback hell, very low CPU and memory usage.
- Simple usage, and you don't have to make everything non-block.
- Prefork production server, with signal-based management which enables graceful restart.
- Route actions with scanf-like DSL.
- Simple request format matcher.
- Optimized render and layout helpers, easy to stream the view.

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

- [Manual](https://github.com/luikore/nyara/wiki/Manual)
- [API doc](http://rubydoc.info/github/luikore/nyara/master/frames)
- [Q & A](https://github.com/luikore/nyara/wiki/Q-&-A)
- [Wiki](https://github.com/luikore/nyara/wiki/Home)

# Participate

- [Building from source](https://github.com/luikore/nyara/wiki/Building)
- Mailing list: [nyara@relist.com](mailto://nyara@relist.com)<br>
  If you fail to subscribe, have a check in the spam filter...
- [Mailing list archive](http://librelist.com/browser/nyara)

# Caveats

- Not based on [rack](https://github.com/rack/rack).
- Not compatible with [eventmachine](https://github.com/eventmachine/eventmachine). It won't work if you add gems like [em-synchrony](https://github.com/igrigorik/em-synchrony).
- Not yet another ruby async framework, some features in a common async IO framework are not implemented.
- Doesn't and won't work on JRuby or lower versions of Ruby.
- Doesn't and won't work on Windows.

# License

BSD 3-Clause, see [copying](https://github.com/luikore/nyara/blob/master/copying)

# Contributors

- [committers](https://github.com/luikore/nyara/contributors)
- hooopo
