# Changelog

All notable changes to saytime-weather-rb are documented here.

## [0.0.7] - 2026-02-20

### Added
- **weather.rb**: `require 'fileutils'` so `create_default_config` works correctly.
- **saytime.rb**: `--log=FILE` appends run and message log with UTC timestamps (started, finished, info/warn/error).

### Changed
- **weather.rb**: `http_get` retries up to 3 times with 1 second delay between attempts.
- **saytime.rb**: Weather and Asterisk failure messages use exit code `-1` when `$?.exitstatus` is nil.

### Notes
- No support for deprecated `/var/lib/asterisk/sounds` (ASL3). Sound paths remain `/usr/share/asterisk/sounds` and `/tmp/`.
- Audio is ulaw-only; gsm is not supported.

## [0.0.6] - 2026-02-16

- saytime.rb: 12-hour clock uses "oh" for leading minute (e.g. 2:06 → "two oh six") via `letters/o.ulaw` when present.
- saytime.rb: Fix help text indentation for `-m/--method`.
- README: Document 12-hour "oh" behavior.

## [0.0.5] - 2026-01-25

- weather.rb: Fix NoMethodError when using airport codes with additional weather data options.

## [0.0.4] - 2026-01-25

- weather.rb: IATA airport code support, additional weather options (precipitation, wind, pressure, humidity), unit conversions.

## [0.0.3] - 2026-01-19

- saytime.rb: Fix custom sound directory validation, improve playback method and timezone sanitization.
- weather.rb: Safe hash access, buffered condition file reading, write_timezone_file helper.

## [0.0.2] - 2026-01-04

- weather.rb: Multi-word condition handling fixed.
- TZ environment variable support for timezone override.

## [0.0.1] - 2025-12-30

- Initial Debian package release; Ruby implementation with no external gem dependencies.

[0.0.7]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/hardenedpenguin/saytime_weather_rb/releases/tag/v0.0.1
