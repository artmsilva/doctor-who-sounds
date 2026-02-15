.PHONY: build install clean daemon-start daemon-stop daemon-restart daemon-status

build:
	cargo build --release

install: build
	mkdir -p bin
	cp target/release/play-sound bin/play-sound

clean:
	cargo clean
	rm -f bin/play-sound

daemon-start:
	./bin/play-sound --daemon &

daemon-stop:
	./bin/play-sound --stop

daemon-restart: daemon-stop daemon-start

daemon-status:
	@if [ -f /tmp/doctor-who-sounds/daemon.pid ]; then \
		pid=$$(cat /tmp/doctor-who-sounds/daemon.pid); \
		if kill -0 $$pid 2>/dev/null; then \
			echo "Daemon running (PID $$pid)"; \
		else \
			echo "Daemon not running (stale PID file)"; \
		fi \
	else \
		echo "Daemon not running"; \
	fi
