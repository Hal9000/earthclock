#!/usr/bin/env ruby
# frozen_string_literal: true

require "gtk3"

module EarthClock
  # Loads an equirectangular Earth texture and exposes sampling by lon/lat
  class EarthModel
    attr_reader :width, :height

    def initialize(texture_path)
      unless File.exist?(texture_path)
        raise ArgumentError, "Texture not found: #{texture_path}"
      end
      @pixbuf = GdkPixbuf::Pixbuf.new(file: texture_path)
      @width = @pixbuf.width
      @height = @pixbuf.height
      @channels = @pixbuf.n_channels
      @rowstride = @pixbuf.rowstride
      @has_alpha = @pixbuf.has_alpha?
      @pixels = @pixbuf.pixels # String-like
      @lon_offset_rad = ((ENV["EC_TEX_LON_OFFSET_DEG"] || "0").to_f) * Math::PI / 180.0
    end

    # dir: Vector [x,y,z] in Earth-fixed (unit). Returns [r,g,b]
    def sample_direction(dir)
      x, y, z = dir.to_a
      lon = Math.atan2(y, x) # [-π, π]
      lat = Math.asin(z)     # [-π/2, π/2]
      sample_lonlat(lon, lat)
    end

    # lon [-π, π], lat [-π/2, π/2]
    def sample_lonlat(lon, lat)
      lon_adj = lon + @lon_offset_rad
      u = (lon_adj + Math::PI) / (2.0 * Math::PI) # [0,1)
      v = (Math::PI / 2.0 - lat) / Math::PI   # [0,1]
      ix = (u * @width).floor % @width
      iy = [[(v * @height).floor, @height - 1].min, 0].max
      sample_pixel(ix, iy)
    end

    private

    def sample_pixel(x, y)
      offset = y * @rowstride + x * @channels
      r = byte_at(offset + 0)
      g = byte_at(offset + 1)
      b = byte_at(offset + 2)
      [r, g, b]
    end

    def byte_at(i)
      if @pixels.respond_to?(:getbyte)
        @pixels.getbyte(i)
      else
        # Some platforms may return an Array-like buffer
        @pixels[i]
      end
    end

    public
    # Heuristic: find vertical seam where adjacent columns match best.
    # Returns [seam_column, suggested_offset_deg]
    def estimate_seam_offset
      best_c = 0
      best_score = Float::INFINITY
      step = [@height / 512, 1].max
      (0...@width).each do |c|
        c_prev = (c - 1) % @width
        score = 0
        y = 0
        while y < @height
          off_a = y * @rowstride + c * @channels
          off_b = y * @rowstride + c_prev * @channels
          dr = (byte_at(off_a + 0) - byte_at(off_b + 0)).abs
          dg = (byte_at(off_a + 1) - byte_at(off_b + 1)).abs
          db = (byte_at(off_a + 2) - byte_at(off_b + 2)).abs
          score += dr + dg + db
          y += step
        end
        if score < best_score
          best_score = score
          best_c = c
        end
      end
      # We want the texture seam at column 0; suggest offset to shift seam to 0
      suggested_offset_deg = -best_c.to_f * 360.0 / @width.to_f
      [best_c, suggested_offset_deg]
    end
  end
end

