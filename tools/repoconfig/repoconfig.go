// Package repoconfig holds the tests that pin the repository's own
// configuration: the CI and release workflows, release-please, the branch
// rulesets and the branch names the docs use. It has no runtime
// code; these helpers only load the files the tests read.
package repoconfig

import (
	"encoding/json"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Root is the repository root, two levels above this package.
func Root() string {
	abs, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		panic(err)
	}
	return abs
}

// LoadYAML decodes a YAML file named relative to the repository root.
func LoadYAML(rel string) (map[string]any, error) {
	b, err := os.ReadFile(filepath.Join(Root(), rel))
	if err != nil {
		return nil, err
	}
	var m map[string]any
	return m, yaml.Unmarshal(b, &m)
}

// LoadJSON decodes a JSON file named relative to the repository root.
func LoadJSON(rel string) (map[string]any, error) {
	b, err := os.ReadFile(filepath.Join(Root(), rel))
	if err != nil {
		return nil, err
	}
	var m map[string]any
	return m, json.Unmarshal(b, &m)
}

// Dig walks nested maps by key and returns nil when a key is missing.
func Dig(v any, path ...string) any {
	for _, k := range path {
		m, ok := v.(map[string]any)
		if !ok {
			return nil
		}
		v = m[k]
	}
	return v
}
