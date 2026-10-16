package sitecheck

import (
	"fmt"
	"strings"

	"rsc.io/qr"
)

// PixKey is a receiver of Pix transfers as the static BR Code names it
// (Manual de Padrões para Iniciação do Pix, BCB): the key, a name of at
// most 25 characters and a city of at most 15, both without accents.
type PixKey struct {
	Key, Name, City string
}

// Pix is the company's key: its CNPJ.
var Pix = PixKey{Key: "41894811000160", Name: "CODING FOR YOU TECNOLOGIA", City: "SALVADOR"}

// PixQRPath is where the generated QR lives, relative to the repository.
const PixQRPath = "site/public/pix-qr.svg"

func tlv(id, value string) string { return fmt.Sprintf("%s%02d%s", id, len(value), value) }

// PixPayload is the static BR Code (EMV MPM) for k: no amount, so the payer
// types it, and the reference "***" a static code carries.
func PixPayload(k PixKey) string {
	body := tlv("00", "01") +
		tlv("26", tlv("00", "br.gov.bcb.pix")+tlv("01", k.Key)) +
		tlv("52", "0000") +
		tlv("53", "986") +
		tlv("58", "BR") +
		tlv("59", k.Name) +
		tlv("60", k.City) +
		tlv("62", tlv("05", "***")) +
		"6304"
	return body + crc16hex([]byte(body))
}

// crc16 is CRC-16/CCITT-FALSE (polynomial 0x1021, initial 0xFFFF), the
// checksum the BR Code's field 63 carries.
func crc16(b []byte) uint16 {
	crc := uint16(0xFFFF)
	for _, c := range b {
		crc ^= uint16(c) << 8
		for i := 0; i < 8; i++ {
			if crc&0x8000 != 0 {
				crc = crc<<1 ^ 0x1021
			} else {
				crc <<= 1
			}
		}
	}
	return crc
}

func crc16hex(b []byte) string { return fmt.Sprintf("%04X", crc16(b)) }

// validCNPJ checks a CNPJ's two check digits.
func validCNPJ(s string) bool {
	if len(s) != 14 {
		return false
	}
	d := make([]int, 14)
	for i, c := range s {
		if c < '0' || c > '9' {
			return false
		}
		d[i] = int(c - '0')
	}
	check := func(n int) int {
		w, sum := 2, 0
		for i := n - 1; i >= 0; i-- {
			sum += d[i] * w
			if w++; w > 9 {
				w = 2
			}
		}
		if r := sum % 11; r >= 2 {
			return 11 - r
		}
		return 0
	}
	return check(12) == d[12] && check(13) == d[13]
}

// PixQRSVG draws the payload's QR as one SVG path, one unit per module
// inside a four-module quiet zone, in the site's ink on paper (ink
// modules on the paper-input colour). The page sizes it.
func PixQRSVG(k PixKey) (string, error) {
	code, err := qr.Encode(PixPayload(k), qr.M)
	if err != nil {
		return "", err
	}
	const quiet = 4
	n := code.Size + 2*quiet
	var d strings.Builder
	for y := 0; y < code.Size; y++ {
		for x := 0; x < code.Size; x++ {
			if !code.Black(x, y) {
				continue
			}
			// Runs of dark modules on a row become one rectangle.
			run := 1
			for x+run < code.Size && code.Black(x+run, y) {
				run++
			}
			fmt.Fprintf(&d, "M%d %dh%dv1h-%dz", x+quiet, y+quiet, run, run)
			x += run - 1
		}
	}
	return fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" shape-rendering="crispEdges">`+
		`<rect width="%d" height="%d" fill="#FFFDF8"/><path fill="#1E5B66" d="%s"/></svg>`+"\n",
		n, n, n, n, d.String()), nil
}
