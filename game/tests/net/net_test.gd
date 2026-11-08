extends GdUnitTestSuite

const Net := preload("res://net/net.gd")
const Protocol := preload("res://net/protocol.gd")

const UNKNOWN_REJECT_REASON := 99


func test_a_reject_with_an_unknown_reason_is_ignored() -> void:
	var net: Net = auto_free(Net.new())
	var reasons: Array[int] = []
	net.rejected.connect(func(reason: Protocol.RejectReason) -> void: reasons.append(reason))
	net.reject(UNKNOWN_REJECT_REASON)
	net.reject(Protocol.RejectReason.FULL)
	assert_array(reasons).contains_exactly([Protocol.RejectReason.FULL])
