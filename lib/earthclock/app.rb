#!/usr/bin/env ruby
# frozen_string_literal: true

require "gtk3"
require "cairo"
require_relative "time_state"
require_relative "astro"
require_relative "earth_model"
require_relative "shading"
require_relative "projector"

module EarthClock
  class App
    DEFAULT_SIZE = 800
    REDRAW_HZ = 1

    def self.run
      new.run
    end

    def initialize
      @size = DEFAULT_SIZE
      @time_source = TimeState.new
      @earth_texture_path = File.expand_path(ENV["EC_TEXTURE"] || File.join(Dir.pwd, "earth.jpg"))
      @earth_model = EarthModel.new(@earth_texture_path)
      @astro = Astro.new
      @shading = Shading.new(
        night_floor: (ENV["EC_NIGHT_FLOOR"] || "0.25").to_f,
        gamma: (ENV["EC_GAMMA"] || "1.0").to_f,
        exposure: (ENV["EC_EXPOSURE"] || "1.6").to_f,
        disabled: ENV["EC_DISABLE_SHADING"] == "1"
      )
      @projector = Projector.new(@size, @size, @earth_model, @astro, @shading)
      @last_frame = nil
    end

    def run
      app = Gtk::Application.new("com.earthclock.app", :flags_none)

      app.signal_connect "activate" do |application|
        @window = Gtk::ApplicationWindow.new(application)
        @window.title = "EarthClock Preview"
        @window.set_default_size(@size, @size)

        drawing_area = Gtk::DrawingArea.new
        drawing_area.set_size_request(@size, @size)
        # Optional fullscreen/monitor placement
        if ENV["EC_FULLSCREEN"] == "1"
          begin
            display = Gdk::Display.default
            monitor_index = Integer(ENV["EC_MONITOR_INDEX"] || "0")
            if display && display.n_monitors > 0
              monitor_index = [[monitor_index, 0].max, display.n_monitors - 1].min
              monitor = display.monitor(monitor_index)
              geo = monitor.geometry
              @window.move(geo.x, geo.y)
            end
            @window.fullscreen
          rescue StandardError
            # Ignore placement errors; keep windowed
          end
        end

        drawing_area.signal_connect("draw") do |_, cr|
          render_frame_if_needed
          # Clear to black
          cr.set_source_rgb(0, 0, 0)
          cr.paint
          # Blit rendered surface
          if @last_frame
            pattern = Cairo::SurfacePattern.new(@last_frame)
            cr.set_source(pattern)
            cr.paint
          end
          true
        end

        @window.add(drawing_area)
        @window.show_all

        # Timer for periodic redraw
        GLib::Timeout.add((1000.0 / REDRAW_HZ).to_i) do
          drawing_area.queue_draw
          true
        end
      end

      app.run
    end

    private

    def render_frame_if_needed
      now = @time_source.now_utc_seconds
      @last_frame = @projector.render(now)
      if ENV["EC_SHOW_COORDS"] == "1" && @window
        slon, slat = @astro.sublunar_lon_lat(now)
        sslon, sslat = @astro.subsolar_lon_lat(now)
        slon_deg = (slon * 180.0 / Math::PI)
        slat_deg = (slat * 180.0 / Math::PI)
        sslon_deg = (sslon * 180.0 / Math::PI)
        sslat_deg = (sslat * 180.0 / Math::PI)
        @window.title = format("EarthClock  SLon %.1f°, SLat %.1f° | Sun Lon %.1f°, Lat %.1f°",
                               slon_deg, slat_deg, sslon_deg, sslat_deg)
        puts @window.title
      end
    end
  end
end

