// Package brandcheck holds the test that keeps the brand files the products
// ship equal to what brand/source/build_brand.py generated. The generator
// records the hash of every file it writes in brand/manifest.sha256; the
// check needs no Python, only the committed files.
package brandcheck

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Root is the repository root, two levels above this package.
func Root() string {
	abs, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		panic(err)
	}
	return abs
}

// Manifest reads brand/manifest.sha256: repository-relative path to the
// hex SHA-256 the generator wrote it with.
func Manifest(root string) (map[string]string, error) {
	f, err := os.Open(filepath.Join(root, "brand", "manifest.sha256"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	out := map[string]string{}
	s := bufio.NewScanner(f)
	for s.Scan() {
		sum, path, ok := strings.Cut(s.Text(), "  ")
		if !ok || len(sum) != 64 || path == "" {
			return nil, fmt.Errorf("malformed manifest line %q", s.Text())
		}
		out[path] = sum
	}
	return out, s.Err()
}

// Hash is the hex SHA-256 of a repository file.
func Hash(root, rel string) (string, error) {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}
