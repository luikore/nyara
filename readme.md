Not Yet Another Ruby Async web framework and server.

[![Build Status](https://travis-ci.org/luikore/nyara.png)](https://travis-ci.org/luikore/nyara)

- Evented IO while API remains synchrony
- Prefork production server
- Sinatra-like http method and scanf-like http path and path helper
- Request format matcher with just `case ... when`
- Easy to stream the view with `Fiber.yield`

**Notice**

- *Nyara* is not based on *rack*.
- *Nyara* is not compatible with *eventmachine*. It won't work if you add gems like *em-synchrony*.

# Getting started

Requirement

- BSD/Linux/Mac OS X
- Ruby 2.0.0-p195 or higher (due to some syntax issues, doesn't work on 2.0.0-p0)
- GCC4.5+ or Clang

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

# Build from source

After cloning

```bash
git submodule update --init
bundle
rake gen
rake gem
```

If you have cloned the repo once, and want to update code

```bash
git pull --recurse-submodules
git submodule foreach git fetch
```

# Testing

Simply run the test

```bash
rspec -c
```

Test in GC.stress mode

```bash
rspec -c -f d
```

With coverage (generates *coverage/index.html*)

```bash
COVERAGE=1 rspec -c
```

# Why fast

### Solid http parsers written in C

Nyara uses two evented parsers:

- [http_parser](https://github.com/joyent/http-parser) with chunked encoding support
- [multipart-parser-c](https://github.com/iafonov/multipart-parser-c) (todo)

And implemented the following in addition:

- RFC2616 compliant `Accept*` parser
- MIME type matcher
- Url-encoded parser for path / query / request body

### Decisive routing on header complete

To support HTTP methods like PUT, DELETE for archaic browsers, a technique called **method override** is used, and the HTTP method can be overriden by a request param (usually named `_method`). In Rack the param may rest in request body, so it needs to parse the whole body before routing to a desired action. In Nyara the param is always in request path query, and routing starts when header completes. So server can do a lot of things before a huge file completely uploaded and provide better user experience.

### Thin evented IO layer built for BSD or Linux

Nyara is only for systems with kqueue or epoll (maybe iocp in the future). Manufactural event queue is a waste of time.

### Solve sequential problems with Fiber

The common caveats of an evented framework is: mutual callbacks must be used to ensure the order of operations. In eventmachine, sent data buffers are copied and chained in a deque to flush, and `close_connection_after_writing` must be called to ensure that all data are written before close.

While in Nyara, the data sending is much simpler: we send them directly, if there are remaining bytes, the action fiber is paused. When the socket is ready again, we wake up the fiber to continue the send action. So a lot of duplications, memory copy and schedule are avoided and `close` is the `close`.

### More stable memory management

To make better user experience, you may tune the server to stop GC while doing request, and start GC again after every serveral requests. But by doing so you are increasing the probability of OOM: there are cases when `malloc` or `new` fails to get memory while the GC stopped by you can release some. With C-ext this can be partly fixed with Ruby's `ALLOC` and `ALLOC_N`, which can make GC release some memory when `malloc` fails. But with C++ this becomes a bit messy: you need to redefine `new` operators.

In Nyara, the use of C++ memory allocation is limited to boot time (the use of C++ may possibly removed in the future) so your server has less chance to be quit by a silent `OutOfMemoryException`.

### Shared buffer in layout rendering

Consider you have a page with nested layout: `layout1` encloses `layout2`, and `layout2` contains `page`.

When rendering `layout2`, the output string of `page` becomes an element inside the array buffer of `layout2`, then the output of `page` is duplicated in the output of `layout2`. When rendering `layout1`, the output of `layout2` is duplicated so a string containing the output of `page` is duplicated, again.

In Nyara, nested templates of Slim, ERB or Haml share the same output buffer, so the duplication is greatly reduced.

# How fast

Performance is feature, there are specs on:

- Accept-* parse vs sinatra
- param parse vs ruby
- layout rendering vs tilt

# License

BSD, see copying
