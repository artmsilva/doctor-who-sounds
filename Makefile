.PHONY: build install clean

build:
	cargo build --release

install: build
	mkdir -p bin
	cp target/release/play-sound bin/play-sound

clean:
	cargo clean
	rm -f bin/play-sound
