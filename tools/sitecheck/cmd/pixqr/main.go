// Command pixqr writes the site's Pix QR.
// Run it from tools/sitecheck after changing sitecheck.Pix.
package main

import (
	"log"
	"os"
	"path/filepath"

	"github.com/c4u-tech/c4u-telinhasegura-platform/tools/sitecheck"
)

func main() {
	svg, err := sitecheck.PixQRSVG(sitecheck.Pix)
	if err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sitecheck.Root(), sitecheck.PixQRPath), []byte(svg), 0o644); err != nil {
		log.Fatal(err)
	}
}
