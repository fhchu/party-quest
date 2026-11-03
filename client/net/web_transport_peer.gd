extends "res://net/client_peer.gd"
## Reliable frames share one stream; the rest go as datagrams, so a lost one
## never holds up the others. Godot has no WebTransport API, hence [constant JS].

## GDScript can only poll JavaScript, so received data waits in an inbox and
## is taken as one buffer per frame: chunks of type u8 (0 stream bytes,
## 1 a datagram), length u32 (little-endian), bytes.
const JS := """
window.pqTransport = window.pqTransport || (() => {
	const conns = new Map();
	let nextId = 1;
	const fromBase64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

	async function read(c, readable, type) {
		const reader = readable.getReader();
		try {
			for (;;) {
				const { value, done } = await reader.read();
				if (done) break;
				c.inbox.push([type, value]);
			}
		} catch (e) {}
		if (type === 0) c.state = 'closed';
	}

	return {
		open(url, certHashUrl, fallbackDatagram) {
			const id = nextId++;
			const c = { state: 'connecting', inbox: [], wt: null, stream: null,
				datagrams: null, maxDatagram: fallbackDatagram };
			conns.set(id, c);
			(async () => {
				try {
					const options = {};
					if (certHashUrl) {
						// A self-signed certificate is trusted only by its hash.
						const hash = (await (await fetch(certHashUrl)).text()).trim();
						options.serverCertificateHashes = [
							{ algorithm: 'sha-256', value: fromBase64(hash) }];
					}
					c.wt = new WebTransport(url, options);
					c.wt.closed.finally(() => { c.state = 'closed'; });
					await c.wt.ready;
					// The relay opens the stream: one opened here wouldn't reach the
					// relay until written to, and nothing is written before the peer ID.
					const incoming = c.wt.incomingBidirectionalStreams.getReader();
					const { value: bidi } = await incoming.read();
					incoming.releaseLock();
					c.stream = bidi.writable.getWriter();
					c.datagrams = c.wt.datagrams.writable.getWriter();
					c.maxDatagram = c.wt.datagrams.maxDatagramSize || fallbackDatagram;
					read(c, bidi.readable, 0);
					read(c, c.wt.datagrams.readable, 1);
					if (c.state === 'connecting') c.state = 'open';
				} catch (e) {
					console.warn('match connection failed:', e);
					c.state = 'closed';
				}
			})();
			return id;
		},

		state(id) {
			const c = conns.get(id);
			return c ? c.state : 'closed';
		},

		take(id) {
			const c = conns.get(id);
			if (!c || c.inbox.length === 0) return null;
			let size = 0;
			for (const [, bytes] of c.inbox) size += 5 + bytes.length;
			const out = new Uint8Array(size);
			const view = new DataView(out.buffer);
			let at = 0;
			for (const [type, bytes] of c.inbox) {
				out[at] = type;
				view.setUint32(at + 1, bytes.length, true);
				out.set(bytes, at + 5);
				at += 5 + bytes.length;
			}
			c.inbox = [];
			return out.buffer;
		},

		sendStream(id, base64) {
			const c = conns.get(id);
			if (c && c.stream) c.stream.write(fromBase64(base64)).catch(() => {});
		},

		// A frame too big for a datagram goes on the stream, so it still arrives.
		sendDatagram(id, base64) {
			const c = conns.get(id);
			if (!c || !c.datagrams) return;
			const bytes = fromBase64(base64);
			if (bytes.length <= c.maxDatagram) {
				c.datagrams.write(bytes).catch(() => {});
				return;
			}
			const framed = new Uint8Array(4 + bytes.length);
			new DataView(framed.buffer).setUint32(0, bytes.length, true);
			framed.set(bytes, 4);
			c.stream.write(framed).catch(() => {});
		},

		close(id) {
			const c = conns.get(id);
			conns.delete(id);
			if (c && c.wt) {
				try { c.wt.close(); } catch (e) {}
			}
		},
	};
})();
"""

var _js: JavaScriptObject
var _handle := 0


## [param cert_hash_url]: where to fetch a self-signed relay certificate's
## hash; empty for a real certificate.
func connect_to(url: String, cert_hash_url: String) -> Error:
	if not OS.has_feature("web"):
		return ERR_UNAVAILABLE
	JavaScriptBridge.eval(JS, true)
	_js = JavaScriptBridge.get_interface("pqTransport")
	_handle = int(_js.open(url, cert_hash_url, Frames.DATAGRAM_BUDGET))
	return OK


func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	# An ArrayBuffer comes back from eval as a PackedByteArray.
	var inbox: Variant = JavaScriptBridge.eval("pqTransport.take(%d)" % _handle, true)
	if inbox is PackedByteArray:
		_read_inbox(inbox)
	if _link.reader.failed or str(_js.state(_handle)) == "closed":
		_lost()


func _put_packet_script(packet: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var frame := _frame(_link, packet)
	if _mode == TRANSFER_MODE_RELIABLE:
		_js.sendStream(_handle, Marshalls.raw_to_base64(Frames.prefixed(frame)))
	else:
		_js.sendDatagram(_handle, Marshalls.raw_to_base64(frame))
	return OK


func _close() -> void:
	if _js:
		_js.close(_handle)
	_status = CONNECTION_DISCONNECTED


func _read_inbox(inbox: PackedByteArray) -> void:
	var at := 0
	while at + 5 <= inbox.size():
		var size := inbox.decode_u32(at + 1)
		var bytes := inbox.slice(at + 5, at + 5 + size)
		if inbox[at] == 0:
			_link.reader.feed(bytes)
			var frame := _link.reader.next()
			while not frame.is_empty():
				_on_frame(frame)
				frame = _link.reader.next()
		elif not bytes.is_empty():
			_on_frame(bytes)
		at += 5 + size
