extends "res://net/client_peer.gd"
## Reliable frames share one stream; the rest go as datagrams, so a lost one
## never holds up the others. Godot has no WebTransport API, hence [constant JS].

## Inbox chunk types.
enum Chunk {
	STREAM,
	DATAGRAM,
	CLOSED,
}

## GDScript can only poll JavaScript, so received data waits in an inbox and
## is taken as one buffer per frame: chunks of type u8 ([enum Chunk]), length
## u32 (little-endian), bytes. Closing is the last chunk, so the peer's
## status is the only connection state. Names in braces are filled in from
## the GDScript constants, so each number is written once.
const JS := """
window.pqTransport = window.pqTransport || (() => {
	const STREAM = {STREAM}, DATAGRAM = {DATAGRAM}, CLOSED = {CLOSED};
	const CHUNK_LENGTH_AT = {CHUNK_LENGTH_AT}, CHUNK_HEADER = {CHUNK_HEADER};
	const conns = new Map();
	let nextId = 1;
	const fromBase64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
	const empty = new Uint8Array(0);

	function closed(c) {
		if (c.closed) return;
		c.closed = true;
		c.inbox.push([CLOSED, empty]);
	}

	async function read(c, readable, type) {
		const reader = readable.getReader();
		try {
			for (;;) {
				const { value, done } = await reader.read();
				if (done) break;
				c.inbox.push([type, value]);
			}
		} catch (e) {}
		if (type === STREAM) closed(c);
	}

	return {
		open(url, certHashUrl, fallbackDatagram) {
			const id = nextId++;
			const c = { closed: false, inbox: [], wt: null, stream: null,
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
					c.wt.closed.finally(() => closed(c));
					await c.wt.ready;
					// The relay opens the stream: one opened here wouldn't reach the
					// relay until written to, and nothing is written before the peer ID.
					const incoming = c.wt.incomingBidirectionalStreams.getReader();
					const { value: bidi } = await incoming.read();
					incoming.releaseLock();
					c.stream = bidi.writable.getWriter();
					// Safari has only createWritable; Chrome may lack it.
					const d = c.wt.datagrams;
					c.datagrams = (d.createWritable ? d.createWritable() : d.writable).getWriter();
					c.maxDatagram = c.wt.datagrams.maxDatagramSize || fallbackDatagram;
					read(c, bidi.readable, STREAM);
					read(c, c.wt.datagrams.readable, DATAGRAM);
				} catch (e) {
					console.warn('match connection failed:', e);
					closed(c);
				}
			})();
			return id;
		},

		take(id) {
			const c = conns.get(id);
			if (!c || c.inbox.length === 0) return null;
			let size = 0;
			for (const [, bytes] of c.inbox) size += CHUNK_HEADER + bytes.length;
			const out = new Uint8Array(size);
			const view = new DataView(out.buffer);
			let at = 0;
			for (const [type, bytes] of c.inbox) {
				out[at] = type;
				view.setUint32(at + CHUNK_LENGTH_AT, bytes.length, true);
				out.set(bytes, at + CHUNK_HEADER);
				at += CHUNK_HEADER + bytes.length;
			}
			c.inbox = [];
			return out.buffer;
		},

		sendStream(id, base64) {
			const c = conns.get(id);
			if (c && c.stream) c.stream.write(fromBase64(base64)).catch(() => {});
		},

		// Frames are kept under the datagram budget (frames.gd), so a bigger
		// one is a bug.
		sendDatagram(id, base64) {
			const c = conns.get(id);
			if (!c || !c.datagrams) return;
			const bytes = fromBase64(base64);
			if (bytes.length > c.maxDatagram) {
				console.error(`dropped a ${bytes.length}-byte frame: ` +
					`datagrams take at most ${c.maxDatagram} bytes`);
				return;
			}
			c.datagrams.write(bytes).catch(() => {});
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

const CHUNK_LENGTH_AT := 1
const CHUNK_HEADER := CHUNK_LENGTH_AT + Frames.U32_SIZE

var _js: JavaScriptObject
var _handle := 0


## Whether this browser has WebTransport. Always false off the web.
static func is_supported() -> bool:
	return (OS.has_feature("web")
			and JavaScriptBridge.eval("typeof WebTransport !== 'undefined'", true) == true)


func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	# An ArrayBuffer comes back from eval as a PackedByteArray.
	var inbox: Variant = JavaScriptBridge.eval("pqTransport.take(%d)" % _handle, true)
	if inbox is PackedByteArray:
		_read_inbox(inbox)


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


## [param cert_hash_url]: where to fetch a self-signed relay certificate's
## hash; empty for a real certificate.
func connect_to(url: String, cert_hash_url: String) -> Error:
	if not OS.has_feature("web"):
		return ERR_UNAVAILABLE
	JavaScriptBridge.eval(JS.format({
		"STREAM": Chunk.STREAM, "DATAGRAM": Chunk.DATAGRAM, "CLOSED": Chunk.CLOSED,
		"CHUNK_LENGTH_AT": CHUNK_LENGTH_AT, "CHUNK_HEADER": CHUNK_HEADER,
	}), true)
	_js = JavaScriptBridge.get_interface("pqTransport")
	_handle = int(_js.open(url, cert_hash_url, Frames.DATAGRAM_BUDGET))
	return OK


func _read_inbox(inbox: PackedByteArray) -> void:
	var at := 0
	while at + CHUNK_HEADER <= inbox.size():
		var size := inbox.decode_u32(at + CHUNK_LENGTH_AT)
		var bytes := inbox.slice(at + CHUNK_HEADER, at + CHUNK_HEADER + size)
		match inbox[at]:
			Chunk.STREAM:
				_link.reader.feed(bytes)
				var frame := _link.reader.next()
				while not frame.is_empty():
					_on_frame(frame)
					frame = _link.reader.next()
				if _link.reader.failed:
					_lost()
					return
			Chunk.DATAGRAM:
				if not bytes.is_empty():
					_on_frame(bytes)
			Chunk.CLOSED:
				_lost()
				return
		at += CHUNK_HEADER + size
