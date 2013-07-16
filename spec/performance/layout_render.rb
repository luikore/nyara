require_relative "performance_helper"
require "slim"

configure do
  set :views, __dir__
end
Nyara::View.init
$page_tilt = Tilt.new __dir__ + '/page.slim'
$layout_tilt = Tilt.new __dir__ + '/layout.slim'

class MyRenderable
  def initialize items
    @title = "layout_render"
    @items = items
  end

  def send_chunk s
    @res ||= []
    @res << s
  end

  def nyara_render
    view = Nyara::View.new self, 'page.slim', ['layout.slim', 'layout.slim'], {items: @items}, {}
    Fiber.new{ view.render }.resume
  end

  def tilt_render
    Fiber.new{}.resume # XXX simulate the overhead of every request
    $layout_tilt.render self do
      $layout_tilt.render self do
        $page_tilt.render self, items: @items
      end
    end
  end
end

def bm_nyara items
  Nyara::Ext.rdtsc_start
  MyRenderable.new(items).nyara_render
  Nyara::Ext.rdtsc
end

def bm_tilt items
  Nyara::Ext.rdtsc_start
  MyRenderable.new(items).tilt_render
  Nyara::Ext.rdtsc
end

# prepare data
Item = Struct.new :name, :price
items = 10.times.map do |i|
  Item.new "name#{i}", i
end
bm_nyara items
bm_tilt items

dump nyara: bm_nyara(items), tilt: bm_tilt(items)
