#!/usr/bin/env ruby
# frozen_string_literal: true

module EarthClock
  class TimeState
    def initialize
      @fixed_seconds = resolve_fixed_time_from_env
    end

    # Returns float seconds since Unix epoch (UTC)
    def now_utc_seconds
      return @fixed_seconds if @fixed_seconds
      Process.clock_gettime(Process::CLOCK_REALTIME)
    end

    private

    def resolve_fixed_time_from_env
      # Explicit UNIX seconds override
      if (unix = ENV["EC_UNIX_SECONDS"]) && !unix.empty?
        return unix.to_f
      end
      # ISO8601 UTC string override, e.g. 1969-07-20T20:17:40Z
      if (iso = ENV["EC_TIME"]) && !iso.empty?
        begin
          t = Time.iso8601(iso)
          return t.to_f
        rescue StandardError
          # ignore parse errors
        end
      end
      # Named presets
      case (ENV["EC_PRESET"] || "").downcase
      when "1stlanding", "apollo11_landing", "landing"
        # Apollo 11 lunar landing time (LM touchdown)
        return Time.utc(1969, 7, 20, 20, 17, 40).to_f
      when "firststep", "apollo11_first_step", "1ststep"
        # Apollo 11 first step on lunar surface
        return Time.utc(1969, 7, 21, 2, 56, 15).to_f
      else
        nil
      end
    end
  end
end

