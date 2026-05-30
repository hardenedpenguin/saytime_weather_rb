# Changelog

All notable changes to saytime-weather-rb are documented here.

## [0.0.17] - 2026-05-19

### Added
- **GPS location**: `location_source = gps` in `weather.ini` or `--gps` on `saytime.rb` / `weather.rb` reads coordinates from **gpsd** (with gpspipe fallback and cached last fix).
- **Coordinate literals**: `-l 48.8566,2.3522` passes lat/lon directly without geocoding.
- **`gps_fallback_location`**: optional postal/airport fallback when GPS has no fix.
- Debian package **Recommends: gpsd**.

### Changed
- **Default config**: `weather_provider_random = YES`; `weather_provider` omitted by default (Open-Meteo tried last during rotation).

## [0.0.16] - 2026-05-19

### Fixed
- **saytime timezone**: Location timezone file from weather now takes priority over `ENV['TZ']`; time lookup uses `date` in the target zone (Ruby `Time.now` does not honor runtime `TZ` changes on typical Linux installs).

## [0.0.15] - 2026-05-19

### Added
- **Geocode cache**: Nominatim results cached on disk (default 30 days) to avoid repeat lookups.
- **Timezone cache**: Open-Meteo timezone lookups cached (default 7 days).
- **Airport map cache**: Parsed IATA/ICAO maps persisted between runs.
- **Sound index**: One-time glob per sound directory for faster existence checks.
- **HTTP keep-alive**: Reuses connections per host; 404 responses are not retried.
- **Configurable tuning** in `weather.ini`: `http_probe_timeout`, `geocode_cache_max_age_seconds`, `timezone_cache_max_age_seconds`, `weather_provider_random_max_attempts`, `saytime_play_delay`.

### Changed
- **Random provider mode**: Shorter probe timeout for alternates; max attempts limit (default 3).
- **Airport weather**: Single Open-Meteo call for timezone and supplemental extras when enabled.
- **saytime**: Local time via Ruby `ENV['TZ']` instead of a `date` subprocess.
- **Playback**: Configurable post-play delay; sound concatenation uses `IO.copy_stream`.

## [0.0.14] - 2026-05-19

### Fixed
- **Non-US locations**: `weather_provider = nws` no longer blocks postal-code weather; Open-Meteo is used instead with proper fallback.
- **Random providers**: Location timezone for saytime is always written via Open-Meteo when metno, wttr, or 7timer wins (fixes wrong local time announcements).
- Clearer failure messages listing all providers attempted.

## [0.0.13] - 2026-05-19

### Added
- **`weather_provider_random`**: optional `YES` in `weather.ini` rotates postal-code weather across providers other than `weather_provider`, with fallback on failure (spreads API load).

## [0.0.12] - 2026-05-19

### Fixed
- **saytime.rb**: Resolve `hours.ulaw`, `hundred.ulaw`, and `a-m`/`p-m` from `en/` or `digits/` (fixes missing-file warnings on stock Asterisk sound layouts).

## [0.0.11] - 2026-05-19

### Added
- **`SaytimeWeather.run_weather`**: in-process weather API (used by `saytime.rb` by default).
- **`lib/saytime_weather/weather_script.rb`**: `WeatherScript` class (shared by CLI and library).
- **`lib/saytime_weather/weather_conditions.rb`**: shared condition normalization.
- **Airport timezone**: IATA/ICAO lookups write timezone via Our Airports coordinates + Open-Meteo.
- **Airport supplemental data**: `show_*` options merge Open-Meteo fields when METAR is used.
- **Unit tests** (`test/all.rb`) and `make test-unit` in CI.
- **saytime.rb**: `-c/--config`, `--weather-subprocess`; forwards `-v`, config, and `weather.ini` settings to weather.

### Fixed
- METAR **Light Rain** parsing (`-RA` no longer classified as generic Rain).
- US auto-NWS only when `weather_provider` is unset/default `openmeteo` (explicit `metno`/`wttr`/`7timer` respected).
- **silent=2** skips building time sound files.
- HTTP warnings always logged to stderr; 7Timer API uses HTTPS.
- NWS observation loop capped at 5 stations.

### Changed
- `weather.rb` is a thin wrapper; weather modules load via `weather_entry.rb` without saytime stack.
- `Makefile` syntax-checks metno, wttr, 7timer, and new library files.

## [0.0.9] - 2026-04-06

### Added
- **`lib/saytime_weather/ini.rb`**: shared `SaytimeWeather::Ini.parse_file` for INI parsing (used by weather and saytime config paths).
- **`lib/saytime_weather/constants.rb`**: `HTTP_BUFFER_SIZE`, saytime default flags, and `SAYTIME_PLAY_DELAY`.
- **Weather modules** (`weather_*`): config, geocoding, airports/METAR, Open-Meteo, NWS, units, helpers, sound assembly; `weather.rb` is a thin entry script that includes them.
- **Saytime modules** (`saytime_*`): CLI, config, logging, time formatting, weather subprocess bridge, playback/concat; `saytime.rb` is a thin entry script that includes them.

### Changed
- **`Paths.weather_script_path`**: resolves `weather.rb` via `SaytimeWeather.root` (consistent with packaged layout).
- **`WeatherHelpers#parse_ini_file`** now delegates to `Ini.parse_file`.

## [0.0.10] - 2026-05-01

### Added
- Weather: new no-key providers: MET Norway (`metno`), wttr.in (`wttr`), 7Timer! (`7timer`).

## [0.0.8] - 2026-04-05

### Added
- **`lib/saytime_weather/`**: shared `VERSION`, `Paths` (env-tunable dirs), `Endpoints` (API base URLs), `Network` (timeouts, retries, airports CSV settings), `HttpClient` (retries, errors).
- **`data/special_locations.json`**: named polar/remote locations for coordinate lookup.
- Optional **`weather.ini`** keys: `http_timeout_short`, `http_timeout_long`, `nominatim_delay`, `http_get_retries`, `http_get_retry_sleep`, `airports_cache_max_age_seconds`, `airports_data_url`.
- Environment variables: `SAYTIME_TMP`, `WEATHER_CONFIG`, `SAYTIME_SOUND_ROOT`, `ASTERISK_BIN`.

### Changed
- Debian package ships `lib/` and `data/` under `/usr/share/saytime-weather-rb/`; scripts load library from there when installed to `/usr/sbin/`.

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

[0.0.14]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.13...v0.0.14
[0.0.13]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.12...v0.0.13
[0.0.12]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.11...v0.0.12
[0.0.11]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.10...v0.0.11
[0.0.9]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.8...v0.0.9
[0.0.10]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.9...v0.0.10
[0.0.8]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/hardenedpenguin/saytime_weather_rb/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/hardenedpenguin/saytime_weather_rb/releases/tag/v0.0.1
