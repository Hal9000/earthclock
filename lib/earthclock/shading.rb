#!/usr/bin/env ruby
# frozen_string_literal: true

module EarthClock
  class Shading
    def initialize(night_floor: 0.25, gamma: 1.0, exposure: 1.6, disabled: false)
      @night_floor = [[night_floor.to_f, 0.0].max, 1.0].min
      @gamma = gamma.to_f
      @exposure = exposure.to_f
      @disabled = disabled
    end

    # n: surface normal (ECEF), s: sun direction (ECEF), unit vectors
    # Returns brightness factor [0..1]
    def brightness(n, s)
      return 1.0 if @disabled
      dot = n[0] * s[0] + n[1] * s[1] + n[2] * s[2]
      lit = [dot, 0.0].max
      lit = lit**@gamma
      (@night_floor + (1.0 - @night_floor) * lit) * @exposure
    end
  end
end

