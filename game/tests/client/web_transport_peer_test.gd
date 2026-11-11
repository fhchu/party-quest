extends GdUnitTestSuite

const WebTransportPeer := preload("res://client/web_transport_peer.gd")


func test_unsupported_off_the_web() -> void:
	assert_bool(WebTransportPeer.is_supported()).is_false()
