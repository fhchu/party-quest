// Package matches records finished matches and pays out their rewards.
//
// A submission carries a client-generated match ID. Submitting the same match
// again is a no-op that reports success, so clients can retry freely after a
// timeout or dropped connection without granting the reward twice.
package matches
