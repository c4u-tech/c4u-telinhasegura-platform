package repoconfig

import (
	"encoding/xml"
	"errors"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// decodePlist reads the next plist value from d: a dict becomes a map, an
// array a slice, true and false a bool, string a string. Other value
// types fail, since the manifest uses none.
func decodePlist(d *xml.Decoder) (any, error) {
	for {
		tok, err := d.Token()
		if err != nil {
			return nil, err
		}
		switch el := tok.(type) {
		case xml.EndElement:
			return nil, io.EOF // the enclosing array or dict ended
		case xml.StartElement:
			switch el.Name.Local {
			case "plist":
				continue
			case "true", "false":
				return el.Name.Local == "true", d.Skip()
			case "string":
				var s string
				return s, d.DecodeElement(&s, &el)
			case "array":
				out := []any{}
				for {
					v, err := decodePlist(d)
					if errors.Is(err, io.EOF) {
						return out, nil
					}
					if err != nil {
						return nil, err
					}
					out = append(out, v)
				}
			case "dict":
				out := map[string]any{}
				for {
					var key string
					tok, err := d.Token()
					for err == nil {
						if _, ok := tok.(xml.StartElement); ok {
							break
						}
						if _, ok := tok.(xml.EndElement); ok {
							return out, nil
						}
						tok, err = d.Token()
					}
					if err != nil {
						return nil, err
					}
					start := tok.(xml.StartElement)
					if start.Name.Local != "key" {
						return nil, errors.New("plist: dict entry without a key")
					}
					if err := d.DecodeElement(&key, &start); err != nil {
						return nil, err
					}
					v, err := decodePlist(d)
					if err != nil {
						return nil, err
					}
					out[key] = v
				}
			default:
				return nil, errors.New("plist: unexpected element " + el.Name.Local)
			}
		}
	}
}

func mustPlist(t *testing.T, rel string) map[string]any {
	t.Helper()
	f, err := os.Open(filepath.Join(Root(), rel))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	v, err := decodePlist(xml.NewDecoder(f))
	if err != nil {
		t.Fatalf("decode %s: %v", rel, err)
	}
	m, ok := v.(map[string]any)
	if !ok {
		t.Fatalf("%s: top level is %T, want a dict", rel, v)
	}
	return m
}

type collected struct {
	linked   bool
	purposes []string
}

// The data the app collects, as the App Store privacy label declares it.
// Advertising Data is the ads the embedded YouTube player may show: the
// app never links them to an account.
var wantCollected = map[string]collected{
	"NSPrivacyCollectedDataTypeName":               {true, []string{"NSPrivacyCollectedDataTypePurposeAppFunctionality"}},
	"NSPrivacyCollectedDataTypeEmailAddress":       {true, []string{"NSPrivacyCollectedDataTypePurposeAppFunctionality"}},
	"NSPrivacyCollectedDataTypeUserID":             {true, []string{"NSPrivacyCollectedDataTypePurposeAppFunctionality"}},
	"NSPrivacyCollectedDataTypeDeviceID":           {true, []string{"NSPrivacyCollectedDataTypePurposeAppFunctionality"}},
	"NSPrivacyCollectedDataTypeOtherUserContent":   {true, []string{"NSPrivacyCollectedDataTypePurposeAppFunctionality"}},
	"NSPrivacyCollectedDataTypeProductInteraction": {true, []string{"NSPrivacyCollectedDataTypePurposeAppFunctionality"}},
	"NSPrivacyCollectedDataTypeOtherDataTypes":     {true, []string{"NSPrivacyCollectedDataTypePurposeAppFunctionality"}},
	"NSPrivacyCollectedDataTypeAdvertisingData":    {false, []string{"NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising"}},
}

func TestPrivacyManifestDeclaresTheCollectedData(t *testing.T) {
	m := mustPlist(t, "app/ios/Runner/PrivacyInfo.xcprivacy")
	if m["NSPrivacyTracking"] != false {
		t.Errorf("NSPrivacyTracking = %v, want false", m["NSPrivacyTracking"])
	}
	entries, ok := m["NSPrivacyCollectedDataTypes"].([]any)
	if !ok {
		t.Fatalf("NSPrivacyCollectedDataTypes = %T, want an array", m["NSPrivacyCollectedDataTypes"])
	}
	seen := map[string]bool{}
	for _, e := range entries {
		typ, _ := Dig(e, "NSPrivacyCollectedDataType").(string)
		want, ok := wantCollected[typ]
		if !ok {
			t.Errorf("undeclared type %q in the manifest", typ)
			continue
		}
		if seen[typ] {
			t.Errorf("%s declared twice", typ)
		}
		seen[typ] = true
		if got := Dig(e, "NSPrivacyCollectedDataTypeLinked"); got != want.linked {
			t.Errorf("%s linked = %v, want %v", typ, got, want.linked)
		}
		if got := Dig(e, "NSPrivacyCollectedDataTypeTracking"); got != false {
			t.Errorf("%s tracking = %v, want false", typ, got)
		}
		if got := strs(t, Dig(e, "NSPrivacyCollectedDataTypePurposes")); !reflect.DeepEqual(got, want.purposes) {
			t.Errorf("%s purposes = %v, want %v", typ, got, want.purposes)
		}
	}
	for typ := range wantCollected {
		if !seen[typ] {
			t.Errorf("%s is missing from the manifest", typ)
		}
	}
}
