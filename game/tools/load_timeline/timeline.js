// Injected into the page's <head> by load_timeline (main.go), before the
// engine loads. Stamps each load stage in ms since navigation start, watches
// for main-thread stalls, and posts it all to /report once the first
// datagram arrives (the game is running) or REPORT_BY_MS passes. The game
// itself isn't changed: every mark comes from what the page can see.
(() => {
	// A stall is the 10 ms timer firing more than 50 ms late.
	const BEAT_MS = 10, STALL_MS = 50;
	// Long enough for a slow browser to load; a report still comes if the
	// game never connects.
	const REPORT_BY_MS = 60000;
	const marks = {}, stalls = [];
	const mark = (name) => { marks[name] ??= performance.now(); };

	let last = performance.now();
	const beat = setInterval(() => {
		const now = performance.now();
		if (now - last > BEAT_MS + STALL_MS) stalls.push([last, now]);
		last = now;
	}, BEAT_MS);

	for (const call of ['instantiate', 'instantiateStreaming']) {
		const real = WebAssembly[call];
		WebAssembly[call] = async (...args) => {
			const result = await real.apply(WebAssembly, args);
			mark('wasm_compiled');
			return result;
		};
	}

	// The engine's first line, printed as it starts up.
	const log = console.log;
	console.log = (...args) => {
		if (String(args[0]).startsWith('Godot Engine v')) mark('engine_started');
		log.apply(console, args);
	};

	// The progress overlay goes once the engine has loaded the main scene.
	addEventListener('DOMContentLoaded', () => {
		const status = document.getElementById('status');
		new MutationObserver((_, observer) => {
			if (!document.contains(status) || getComputedStyle(status).display === 'none'
				|| getComputedStyle(status).visibility === 'hidden') {
				mark('bar_hidden');
				observer.disconnect();
			}
		}).observe(document.documentElement, { attributes: true, childList: true, subtree: true });
	});

	// The game's own transport code reads these streams; a read that yields a
	// value stamps its mark. Without WebTransport the page shows its own
	// unsupported-browser message, so it's left undefined.
	const watched = new WeakMap();
	const RealWebTransport = window.WebTransport;
	if (RealWebTransport) {
		window.WebTransport = class extends RealWebTransport {
			constructor(...args) {
				super(...args);
				this.ready.then(() => mark('transport_ready'), () => {});
				watched.set(this.incomingBidirectionalStreams, 'stream_open');
				watched.set(this.datagrams.readable, 'first_datagram');
			}
		};
	}
	const getReader = ReadableStream.prototype.getReader;
	ReadableStream.prototype.getReader = function (...args) {
		const reader = getReader.apply(this, args);
		const name = watched.get(this);
		if (name) {
			const read = reader.read;
			reader.read = async (...readArgs) => {
				const result = await read.apply(reader, readArgs);
				if (!result.done) {
					mark(name);
					if (name === 'first_datagram') report();
				}
				return result;
			};
		}
		return reader;
	};

	let reported = false;
	async function report() {
		if (reported) return;
		reported = true;
		clearInterval(beat);
		for (const entry of performance.getEntriesByType('resource')) {
			const path = new URL(entry.name).pathname;
			if (path.endsWith('.wasm')) marks.wasm_downloaded ??= entry.responseEnd;
			else if (path.endsWith('.pck')) marks.pck_downloaded ??= entry.responseEnd;
		}
		const response = await fetch('/report', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ user_agent: navigator.userAgent, marks, stalls }),
		});
		(response.ok ? console.log : console.error)(await response.text());
	}
	setTimeout(report, REPORT_BY_MS);
})();
