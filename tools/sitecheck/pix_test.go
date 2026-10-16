package sitecheck

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCRC16MatchesTheCCITTFalseCheckValue(t *testing.T) {
	if got := crc16([]byte("123456789")); got != 0x29B1 {
		t.Fatalf("crc16 = %04X, want 29B1", got)
	}
}

// A static BR Code for the key, no amount, valid CRC.
func TestPixPayloadIsAStaticBRCodeForTheKey(t *testing.T) {
	p := PixPayload(Pix)
	for _, field := range []string{
		"000201",
		"26360014br.gov.bcb.pix0114" + Pix.Key,
		"52040000", "5303986", "5802BR",
		"5925CODING FOR YOU TECNOLOGIA",
		"6008SALVADOR",
		"62070503***",
	} {
		if !strings.Contains(p, field) {
			t.Errorf("payload %q lacks %q", p, field)
		}
	}
	ids := []string{}
	for rest := p; rest != ""; {
		if len(rest) < 4 {
			t.Fatalf("payload %q has a truncated field", p)
		}
		n := int(rest[2]-'0')*10 + int(rest[3]-'0')
		if len(rest) < 4+n {
			t.Fatalf("payload %q has a field longer than itself", p)
		}
		ids = append(ids, rest[:2])
		rest = rest[4+n:]
	}
	if got := strings.Join(ids, " "); got != "00 26 52 53 58 59 60 62 63" {
		t.Errorf("fields = %s (no amount, 54, may appear)", got)
	}
	body, crc := p[:len(p)-4], p[len(p)-4:]
	if !strings.HasSuffix(body, "6304") {
		t.Fatalf("payload %q does not end in the CRC field", p)
	}
	if want := crc16hex([]byte(body)); crc != want {
		t.Errorf("CRC = %s, want %s", crc, want)
	}
}

func TestPixKeyIsTheCompanyCNPJ(t *testing.T) {
	if Pix.Key != "41894811000160" {
		t.Errorf("key = %s", Pix.Key)
	}
	if !validCNPJ(Pix.Key) {
		t.Errorf("%s is not a valid CNPJ", Pix.Key)
	}
}

// The committed QR is exactly what the generator writes.
func TestCommittedPixQRMatchesTheGenerator(t *testing.T) {
	want, err := PixQRSVG(Pix)
	if err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(Root(), PixQRPath))
	if err != nil {
		t.Fatalf("%v (run: go run ./cmd/pixqr from tools/sitecheck)", err)
	}
	if string(got) != want {
		t.Errorf("%s is stale (run: go run ./cmd/pixqr from tools/sitecheck)", PixQRPath)
	}
}
