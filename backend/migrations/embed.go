// Package migrations embeds the goose SQL migrations into the binary.
package migrations

import "embed"

// FS holds the goose migrations, applied in file-name order.
//
//go:embed *.sql
var FS embed.FS
