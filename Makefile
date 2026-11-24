# Makefile for saytime-weather-rb

.PHONY: build clean install package test test-unit test-standalone

build:
	@echo "No build step needed - Ruby scripts are interpreted"

clean:
	rm -rf debian/saytime-weather-rb
	rm -rf debian/.debhelper
	rm -f debian/files
	rm -f debian/substvars
	rm -f debian/*.debhelper.log
	rm -f debian/*.substvars

install:
	@echo "Use 'dpkg-buildpackage' to create Debian package"

package:
	dpkg-buildpackage -us -uc -b

# Syntax-check every Ruby file (new modules are picked up automatically).
RUBY_SOURCES := weather.rb saytime.rb $(shell find lib test -name '*.rb' | sort)

test:
	@echo "Running basic syntax checks..."
	@for f in $(RUBY_SOURCES); do \
		ruby -c "$$f" >/dev/null || { echo "Syntax error in $$f"; exit 1; }; \
	done
	@echo "Syntax checks passed ($(words $(RUBY_SOURCES)) files)!"

test-unit:
	ruby test/all.rb

# Run each test file on its own so a missing require cannot hide behind load order.
test-standalone:
	@for f in test/*_test.rb test/saytime_regression_audit.rb; do \
		ruby "$$f" >/dev/null || { echo "FAIL: $$f"; exit 1; }; \
	done; echo "standalone tests: ok"

.DEFAULT_GOAL := build

