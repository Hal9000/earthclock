#!/usr/bin/env ruby
# frozen_string_literal: true

require "matrix"
require "gtk3"

module EarthClock
  class Projector
    # Hardcoded longitudinal fudge to align our simplified geometry
    # (circular lunar orbit, no libration) and texture conventions with a
    # well‑known reference renderer (Fourmilab Earth View).
    #
    # Rationale:
    # - Small constant east/west disagreement can arise from differing
    #   meridian conventions and texture seam placement.
    # - Larger steady offsets (hours) can result from our coarse Moon model
    #   compared to higher‑fidelity references.
    # We apply a fixed yaw about Earth's Z before projection so continents
    # line up visually with the reference. Adjust if you later adopt a
    # higher‑accuracy ephemeris or a different texture seam.
    FUDGE_LON_DEG = -200.0

    def initialize(width, height, earth_model, astro, shading)
      @width = width
      @height = height
      @earth_model = earth_model
      @astro = astro
      @shading = shading
      @test_pattern = ENV["EC_TEST_PATTERN"] == "1"
      # Ocean highlight controls
      @water_boost = (ENV["EC_WATER_BOOST"] || "1.15").to_f
      @water_hue_lo = (ENV["EC_WATER_HUE_LO"] || "180").to_f # degrees
      @water_hue_hi = (ENV["EC_WATER_HUE_HI"] || "250").to_f # degrees
      @water_sat_min = (ENV["EC_WATER_SAT_MIN"] || "0.2").to_f
      @size = [@width, @height].min
      @cx = @width / 2.0
      @cy = @height / 2.0
      @radius = (@size / 2.0).floor
    end

    # Render a Cairo::ImageSurface (ARGB32)
    def render(unix_seconds)
      gmst = @astro.gmst_rad(unix_seconds)
      sun_eci  = @astro.sun_direction_eci(unix_seconds)
      moon_eci = @astro.moon_direction_eci(unix_seconds)
      sun_ecef  = @astro.eci_to_ecef(sun_eci, gmst)
      moon_ecef = @astro.eci_to_ecef(moon_eci, gmst)

      # View basis (Apollo 11 lunar-up) using simplified lunar orientation:
      # - f (+Z) points Earth -> Moon (sub‑lunar hemisphere)
      f = normalize_vec(moon_ecef)
      # Apollo 11 site selenographic coordinates (deg)
      phi_deg  = 0.67408
      lam_deg  = 23.47297 # East positive
      phi  = deg2rad(phi_deg)
      # Use west-positive for body-fixed rotation convention
      lamb = deg2rad(-lam_deg)
      # Site vector in Moon body-fixed frame
      r_site = Vector[Math.cos(phi) * Math.cos(lamb), Math.cos(phi) * Math.sin(lamb), Math.sin(phi)]
      # Lunar pole orientation (IAU 2000 approx) in ECI
      alpha_p = deg2rad(269.9949) # RA
      delta_p = deg2rad(66.5392)  # Dec
      # Prime meridian angle W (deg) ~ synchronous rotation
      d = days_since_j2000(unix_seconds)
      w = deg2rad(38.3213 + 13.17635815 * d)
      # Moon-fixed -> ECI rotation: R3(alpha_p + 90°) * R1(90° - delta_p) * R3(w)
      m_moon_to_eci = rot_z(alpha_p + Math::PI / 2.0) * rot_x(Math::PI / 2.0 - delta_p) * rot_z(w)
      n_site_eci = m_moon_to_eci * r_site
      # Convert to ECEF
      n_site_ecef = @astro.eci_to_ecef(n_site_eci, gmst)
      # Project local vertical onto sky plane for image 'up'
      u_proj = subtract_vec(n_site_ecef, scale_vec(f, dot_vec(n_site_ecef, f)))
      u = normalize_vec(u_proj)
      # Use right-handed basis with x = u × f (avoids left-right mirroring)
      r = normalize_vec(cross_vec(u, f))

      # ECEF -> View matrix with rows as basis vectors (r, u, f)
      r_ecef_to_view = Matrix[
        [r[0], r[1], r[2]],
        [u[0], u[1], u[2]],
        [f[0], f[1], f[2]]
      ]
      # Apply constant longitudinal fudge (yaw about Earth Z, degrees east)
      fudge_rad = FUDGE_LON_DEG * Math::PI / 180.0
      r_ecef_to_view = r_ecef_to_view * rot_z(fudge_rad)
      # Apply constant roll calibration about view Z (clockwise positive on screen)
      # Previous trim put north 180° off; add 180° to correct.
      roll_deg = 225.0
      roll_rad = roll_deg * Math::PI / 180.0
      r_ecef_to_view = rot_z(roll_rad) * r_ecef_to_view

      surface = Cairo::ImageSurface.new(:argb32, @width, @height)
      ctx = Cairo::Context.new(surface)
      # Clear background to black
      ctx.set_source_rgb(0, 0, 0)
      ctx.paint

      # Precompute inverse rotation to map view->ECEF for sampling
      r_view_to_ecef = r_ecef_to_view.transpose

      y0 = (@cy - @radius).to_i
      y1 = (@cy + @radius).to_i
      x0 = (@cx - @radius).to_i
      x1 = (@cx + @radius).to_i

      (0...@height).each do |y|
        (0...@width).each do |x|
          # Outside bounding square fast path
          next if y < y0 || y > y1 || x < x0 || x > x1
          # Normalize to unit disk coords, with +Y up
          dx = (x + 0.5 - @cx) / @radius
          dy = - (y + 0.5 - @cy) / @radius
          r2 = dx * dx + dy * dy
          next if r2 > 1.0
          dz = Math.sqrt(1.0 - r2)
          # View-space normal
          nx_v = dx
          ny_v = dy
          nz_v = dz
          if @test_pattern
            r_col = (dx * 0.5 + 0.5)
            g_col = (dy * 0.5 + 0.5)
            b_col = dz
          else
            # Transform to ECEF
            nx_e, ny_e, nz_e = mul_mat_vec(r_view_to_ecef, nx_v, ny_v, nz_v)
            # Sample texture color
            rr, gg, bb = @earth_model.sample_lonlat(Math.atan2(ny_e, nx_e), Math.asin(nz_e))
            # Shading
            bright = @shading.brightness([nx_e, ny_e, nz_e], sun_ecef)
            r_col = clamp01((rr * bright) / 255.0)
            g_col = clamp01((gg * bright) / 255.0)
            b_col = clamp01((bb * bright) / 255.0)
            # Ocean boost (classify using original texture color)
            if ocean_pixel?(rr, gg, bb)
              r_col = clamp01(r_col * @water_boost)
              g_col = clamp01(g_col * @water_boost)
              b_col = clamp01(b_col * @water_boost)
            end
          end
          ctx.set_source_rgb(r_col, g_col, b_col)
          ctx.rectangle(x, y, 1, 1)
          ctx.fill
        end
      end

      if ENV["EC_DEBUG_OVERLAY"] == "1"
        draw_debug_overlay(ctx, r_ecef_to_view, sun_ecef)
      end
      surface
    end

    private
    def draw_debug_overlay(ctx, r_ecef_to_view, sun_ecef)
      ctx.set_line_width([@radius * 0.002, 1.0].max)
      # Earth axis arrow (blue)
      axis_v = r_ecef_to_view * Vector[0.0, 0.0, 1.0]
      draw_arrow(ctx, axis_v, 0.9, [0.2, 0.6, 1.0])
      # Sun direction projected (yellow)
      sun_v = r_ecef_to_view * sun_ecef
      draw_arrow(ctx, sun_v, 0.9, [1.0, 0.8, 0.1])
      # Terminator great circle (dim gray)
      draw_terminator(ctx, r_ecef_to_view, sun_ecef, [0.5, 0.5, 0.5])
    end

    def draw_arrow(ctx, vec_view, len_scale, rgb)
      vx, vy, vz = vec_view.to_a
      return if vz <= 0.0
      mag = Math.sqrt(vx * vx + vy * vy)
      return if mag < 1e-6
      ux = vx / mag
      uy = vy / mag
      x0 = @cx
      y0 = @cy
      x1 = x0 + ux * @radius * len_scale
      y1 = y0 - uy * @radius * len_scale
      ctx.set_source_rgb(*rgb)
      ctx.move_to(x0, y0)
      ctx.line_to(x1, y1)
      ctx.stroke
      # Simple arrow head
      ah = @radius * 0.04
      left_x = x1 - uy * ah * 0.5 - ux * ah
      left_y = y1 - (-ux) * ah * 0.5 + uy * ah
      right_x = x1 + uy * ah * 0.5 - ux * ah
      right_y = y1 + (-ux) * ah * 0.5 + uy * ah
      ctx.move_to(x1, y1)
      ctx.line_to(left_x, left_y)
      ctx.line_to(right_x, right_y)
      ctx.close_path
      ctx.fill
    end

    def draw_terminator(ctx, r_ecef_to_view, sun_ecef, rgb)
      # Great circle plane normal = sun_ecef
      s = sun_ecef
      # Build basis b1, b2 perpendicular to s
      t = Vector[1.0, 0.0, 0.0]
      t = Vector[0.0, 1.0, 0.0] if (s[0].abs > 0.9)
      b1 = normalize_vec(cross_vec(s, t))
      b2 = normalize_vec(cross_vec(s, b1))
      ctx.set_source_rgb(*rgb)
      ctx.set_dash([@radius * 0.01], 0) rescue nil
      first = true
      prev_vis = false
      0.upto(360) do |deg|
        a = deg * Math::PI / 180.0
        p = add_vec(scale_vec(b1, Math.cos(a)), scale_vec(b2, Math.sin(a)))
        v = r_ecef_to_view * p
        if v[2] > 0.0
          x = @cx + v[0] * @radius
          y = @cy - v[1] * @radius
          if first || !prev_vis
            ctx.move_to(x, y)
          else
            ctx.line_to(x, y)
          end
          first = false
          prev_vis = true
        else
          prev_vis = false
        end
      end
      ctx.stroke
      ctx.set_dash([], 0) rescue nil
    end

    def dot_vec(a, b)
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    end

    def clamp01(x)
      x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x)
    end

    def scale_vec(v, s)
      Vector[v[0] * s, v[1] * s, v[2] * s]
    end

    def add_vec(a, b)
      Vector[a[0] + b[0], a[1] + b[1], a[2] + b[2]]
    end

    def subtract_vec(a, b)
      Vector[a[0] - b[0], a[1] - b[1], a[2] - b[2]]
    end

    def vec_length(v)
      Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    end

    def normalize_vec(v)
      len = vec_length(v)
      return Vector[0.0, 0.0, 0.0] if len < 1e-12
      scale_vec(v, 1.0 / len)
    end

    def cross_vec(a, b)
      Vector[
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0]
      ]
    end

    def rot_x(a)
      ca = Math.cos(a)
      sa = Math.sin(a)
      Matrix[
        [1.0, 0.0, 0.0],
        [0.0,  ca, -sa],
        [0.0,  sa,  ca]
      ]
    end

    def rot_z(a)
      ca = Math.cos(a)
      sa = Math.sin(a)
      Matrix[
        [ ca, -sa, 0.0],
        [ sa,  ca, 0.0],
        [0.0, 0.0, 1.0]
      ]
    end

    def rot_y(a)
      ca = Math.cos(a)
      sa = Math.sin(a)
      Matrix[
        [ ca, 0.0, sa],
        [0.0, 1.0, 0.0],
        [-sa, 0.0, ca]
      ]
    end

    def mul_mat_vec(m, x, y, z)
      [
        m[0, 0] * x + m[0, 1] * y + m[0, 2] * z,
        m[1, 0] * x + m[1, 1] * y + m[1, 2] * z,
        m[2, 0] * x + m[2, 1] * y + m[2, 2] * z
      ]
    end

    def deg2rad(d)
      d * Math::PI / 180.0
    end

    def days_since_j2000(unix_seconds)
      jd = 2440587.5 + unix_seconds / 86400.0
      jd - 2451545.0
    end

    # Heuristic ocean classifier using HSV
    def ocean_pixel?(r8, g8, b8)
      r = r8 / 255.0
      g = g8 / 255.0
      b = b8 / 255.0
      h, s, _v = rgb_to_hsv(r, g, b)
      # Water tends toward blue/cyan hues with some saturation
      (h >= @water_hue_lo && h <= @water_hue_hi && s >= @water_sat_min)
    end

    # Returns hue in degrees [0,360), sat [0,1], val [0,1]
    def rgb_to_hsv(r, g, b)
      max = [r, g, b].max
      min = [r, g, b].min
      v = max
      d = max - min
      s = max.zero? ? 0.0 : d / max
      h = 0.0
      if d.zero?
        h = 0.0
      else
        case max
        when r
          h = (g - b) / d + (g < b ? 6.0 : 0.0)
        when g
          h = (b - r) / d + 2.0
        else
          h = (r - g) / d + 4.0
        end
        h *= 60.0
      end
      [h, s, v]
    end
  end
end

