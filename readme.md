Not Yet Another Ruby Async web framework and server. Not on rack nor rack-compatible neither eventmachine.

# Install

```bash
gem ins nyara
```

# Hello world

```ruby
require 'nyara'
get '/' do
  send_string 'hello world'
end
```

# Develop

```bash
git submodule update --recursive
rake gen
rake gem
```

# Why fast

## Solid http parsers written in C

These evented parsers are used:

- http_parser with chunked encoding support
- multipart request parser

And these are implemented in addition:

- RFC2616 compliant `Accept*` parser
- MIME type matcher
- Url-encoded parser for path / query / request body

## Decisive routing on header complete

To support HTTP methods like PUT, DELETE for archaic browsers, a technique called **method override** is used, and the HTTP method can be overriden by a request param (usually named `_method`). In Rack the param may rest in request body, so it needs to parse the whole body before routing to a desired action. In Nyara the param is always in request path query, and routing starts when header completes. So server can do a lot of things before a huge file completely uploaded and provide better user experience.

## Thin evented IO layer built for BSD or Linux

Nyara is only for systems have kqueue or epoll. Manufactural event queue is a waste of time.

## Solve sequential problems with Fiber

The common caveats of an evented framework is: mutual callbacks must be used to ensure the order of operations. In eventmachine, sent data buffers are copied and chained in a deque to flush, and `close_connection_after_writing` must be called to ensure that all data are written before close.

While in Nyara, the data sending is much simpler: we send them directly, if there are remaining bytes, the action fiber is paused. When the socket is ready again, we wake up the fiber to continue the send action. So a lot of duplications, memory copy and schedule are avoided and `close` is the `close`.

## More stable memory management

To make better user experience, you may tune the server to stop GC while doing request, and start GC again after every serveral requests. But by doing so you are increasing the probability of OOM: there are cases when `malloc` or `new` fails to get memory while the GC stopped by you can release some. With C-ext this can be partly fixed with Ruby's `ALLOC` and `ALLOC_N`, which can make GC release some memory when `malloc` fails. But with C++ this becomes a bit messy: you need to redefine `new` operators.

In Nyara, the use of C++ memory allocation is limited to boot time (the use of C++ may possibly removed in the future) so your server has less chance to be quit by a silent `OutOfMemoryException`.

## Shared buffer in layout rendering

Consider you have a page with nested layout: `layout1` encloses `layout2`, and `layout2` contains `page`.

When rendering `layout2`, the output string of `page` becomes an element inside the array buffer of `layout2`, then the output of `page` is duplicated in the output of `layout2`. When rendering `layout1`, the output of `layout2` is duplicated so a string containing the output of `page` is duplicated, again.

In Nyara, nested templates of Slim, ERB or Haml share the same output buffer, so the duplication is greatly reduced.

# How fast

Performance is feature, there are specs on (TODO):

- Accept-* parse vs rack
- MIME matching vs rack
- param parse vs ruby
- layout rendering vs tilt
- evented IO vs eventmachine
