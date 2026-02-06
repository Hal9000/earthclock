#!/usr/bin/env ruby
# frozen_string_literal: true

require "matrix"

module EarthClock
  class Astro
    # Constants
    DEG2RAD = Math::PI / 180.0
    RAD2DEG = 180.0 / Math::PI
    TWO_PI = 2.0 * Math::PI
    J2000_JD = 2451545.0
    SECONDS_PER_DAY = 86_400.0

    # Simplified, adequate for ~1–2° solar accuracy and coarse lunar phasing
    def initialize(obliquity_deg: 23.439)
      @eps = obliquity_deg * DEG2RAD
    end

    # Returns GMST angle in radians [0, 2π)
    def gmst_rad(unix_seconds)
      jd = julian_day(unix_seconds)
      t = (jd - J2000_JD) / 36525.0
      # GMST in seconds (IAU approximation)
      gmst_sec = 67310.54841 +
                 (876600.0 * 3600 + 8640184.812866) * t +
                 0.093104 * t**2 -
                 6.2e-6 * t**3
      gmst_rad = ((gmst_sec % SECONDS_PER_DAY) / SECONDS_PER_DAY.to_f) * TWO_PI
      gmst_rad += TWO_PI if gmst_rad.negative?
      gmst_rad
    end

    # Sun direction in ECI (unit vector)
    def sun_direction_eci(unix_seconds)
      n = days_since_j2000(unix_seconds)
      # Mean longitude and anomaly (deg)
      l = (280.460 + 0.9856474 * n) % 360.0
      g = (357.528 + 0.9856003 * n) % 360.0
      l_rad = l * DEG2RAD
      g_rad = g * DEG2RAD
      # Ecliptic longitude (deg) -> rad
      lambda_rad = (l + 1.915 * Math.sin(g_rad) + 0.020 * Math.sin(2.0 * g_rad)) * DEG2RAD
      # Obliquity (rad)
      eps = @eps
      # Equatorial coordinates
      alpha = Math.atan2(Math.cos(eps) * Math.sin(lambda_rad), Math.cos(lambda_rad))
      delta = Math.asin(Math.sin(eps) * Math.sin(lambda_rad))
      # Unit vector in ECI
      cosd = Math.cos(delta)
      Vector[
        cosd * Math.cos(alpha),
        cosd * Math.sin(alpha),
        Math.sin(delta)
      ]
    end

    # Moon direction in ECI (unit vector), crude circular orbit in ecliptic plane
    def moon_direction_eci(unix_seconds)
      n = days_since_j2000(unix_seconds)
      # Mean ecliptic longitude of Moon, very rough (deg)
      lambda_deg = (218.316 + 13.176396 * n) % 360.0
      lambda_rad = lambda_deg * DEG2RAD
      eps = @eps
      alpha = Math.atan2(Math.cos(eps) * Math.sin(lambda_rad), Math.cos(lambda_rad))
      delta = Math.asin(Math.sin(eps) * Math.sin(lambda_rad))
      cosd = Math.cos(delta)
      Vector[
        cosd * Math.cos(alpha),
        cosd * Math.sin(alpha),
        Math.sin(delta)
      ]
    end

    # Rotate a vector from ECI to ECEF given GMST
    def eci_to_ecef(vec, gmst_rad)
      cz = Math.cos(gmst_rad)
      sz = Math.sin(gmst_rad)
      # Rotation about Z by +GMST
      x = cz * vec[0] + -sz * vec[1]
      y = sz * vec[0] +  cz * vec[1]
      z = vec[2]
      Vector[x, y, z]
    end

    # Subsolar lon/lat (radians)
    def subsolar_lon_lat(unix_seconds)
      gmst = gmst_rad(unix_seconds)
      sun_eci = sun_direction_eci(unix_seconds)
      sun_ecef = eci_to_ecef(sun_eci, gmst)
      lon = Math.atan2(sun_ecef[1], sun_ecef[0])
      lat = Math.asin(sun_ecef[2])
      [lon, lat]
    end

    # Sublunar lon/lat (radians)
    def sublunar_lon_lat(unix_seconds)
      gmst = gmst_rad(unix_seconds)
      moon_eci = moon_direction_eci(unix_seconds)
      moon_ecef = eci_to_ecef(moon_eci, gmst)
      lon = Math.atan2(moon_ecef[1], moon_ecef[0])
      lat = Math.asin(moon_ecef[2])
      [lon, lat]
    end

    private

    def julian_day(unix_seconds)
      # Algorithm: Unix epoch 1970-01-01T00:00:00Z => JD 2440587.5
      2440587.5 + unix_seconds / SECONDS_PER_DAY
    end

    def days_since_j2000(unix_seconds)
      julian_day(unix_seconds) - J2000_JD
    end
  end
end

