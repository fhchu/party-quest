// Package items embeds items.json, the list of every item that exists. It is
// the single source of truth: the backend copies it into the item table at
// startup, so adding an item is an edit here, not a migration.
//
// A retired item stays in the file with a disabled_at time (RFC 3339),
// because ledger rows keep its ID.
package items

import _ "embed"

//go:embed items.json
var raw []byte
