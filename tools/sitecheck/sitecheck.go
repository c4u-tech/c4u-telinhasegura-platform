// Package sitecheck holds the tests that pin the public site's pages. The
// site is static HTML in site/public; these helpers only read it.
package sitecheck

import (
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/net/html"
)

// The places the site may link outside itself.
const (
	AppURL       = "https://app.telinhasegura.coding4u.tech"
	RepoURL      = "https://github.com/c4u-tech/c4u-telinhasegura-platform"
	SupportEmail = "suporte@telinhasegura.coding4u.tech"
	PrivacyEmail = "privacidade@telinhasegura.coding4u.tech"
	// CurationEmail receives the applications to join the curation team.
	CurationEmail = "curadoria@telinhasegura.coding4u.tech"
	// ReportEmail is the public channel for reports of content that
	// violates children's rights, open to anyone, with or without an account.
	ReportEmail = "denuncia@telinhasegura.coding4u.tech"
	// The policies the YouTube API Services terms ask the pages to link.
	GooglePrivacyURL = "https://www.google.com/policies/privacy"
	YouTubeTermsURL  = "https://www.youtube.com/t/terms"
)

// Root is the repository root, two levels above this package.
func Root() string {
	abs, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		panic(err)
	}
	return abs
}

// Page is what the tests read from one HTML page.
type Page struct {
	Lang, Title string
	Meta        map[string]string
	H1          int
	// Props are the <meta property> tags (Open Graph), by property.
	Props map[string]string
	// Canonical is the page's rel=canonical address: it names the page,
	// it does not fetch anything, so it is not one of Loads.
	Canonical string
	// JSONLD are the raw bodies of <script type="application/ld+json">:
	// structured data the browser never runs, so not inline scripts.
	JSONLD []string
	// Text is the visible text, whitespace collapsed.
	Text string
	// Hrefs are every anchor's href, HrefTexts its text, in order.
	Hrefs, HrefTexts []string
	// Loads are every URL the page fetches: script src, link href, img src.
	Loads []string
	// FooterHrefs and FooterText come from the page's <footer>.
	FooterHrefs []string
	FooterText  string
	IDs         []string
	// InlineScripts counts <script> elements with a body and no src.
	InlineScripts, StyleElements, StyleAttrs int
}

// LoadPage reads the page nginx serves for an URL path: "/" is index.html,
// "/x" is x.html (site/nginx.conf).
func LoadPage(urlPath string) (*Page, error) {
	name := strings.TrimPrefix(urlPath, "/")
	if name == "" {
		name = "index"
	}
	f, err := os.Open(filepath.Join(Root(), "site", "public", name+".html"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	doc, err := html.Parse(f)
	if err != nil {
		return nil, err
	}
	p := &Page{Meta: map[string]string{}, Props: map[string]string{}}
	var text, footer strings.Builder
	var walk func(n *html.Node, inFooter, inHead bool)
	walk = func(n *html.Node, inFooter, inHead bool) {
		if n.Type == html.TextNode && !inHead {
			text.WriteString(n.Data)
			if inFooter {
				footer.WriteString(n.Data)
			}
		}
		// Elements part words, except <wbr>, which only marks where a line
		// may break (an address's break points, the Plain Address Rule).
		if n.Type == html.ElementNode && n.Data != "wbr" {
			text.WriteString(" ")
			if inFooter {
				footer.WriteString(" ")
			}
		}
		if n.Type == html.ElementNode {
			a := attrs(n)
			if a["style"] != "" {
				p.StyleAttrs++
			}
			if id := a["id"]; id != "" {
				p.IDs = append(p.IDs, id)
			}
			switch n.Data {
			case "html":
				p.Lang = a["lang"]
			case "head":
				inHead = true
			case "title":
				p.Title = strings.TrimSpace(innerText(n))
			case "meta":
				if a["name"] != "" {
					p.Meta[a["name"]] = a["content"]
				}
				if a["property"] != "" {
					p.Props[a["property"]] = a["content"]
				}
			case "h1":
				p.H1++
			case "footer":
				inFooter = true
			case "a":
				p.Hrefs = append(p.Hrefs, a["href"])
				p.HrefTexts = append(p.HrefTexts, collapse(innerText(n)))
				if inFooter {
					p.FooterHrefs = append(p.FooterHrefs, a["href"])
				}
			case "script":
				if a["type"] == "application/ld+json" {
					p.JSONLD = append(p.JSONLD, innerText(n))
					return
				}
				if a["src"] != "" {
					p.Loads = append(p.Loads, a["src"])
				} else if strings.TrimSpace(innerText(n)) != "" {
					p.InlineScripts++
				}
				return
			case "style":
				p.StyleElements++
				return
			case "link":
				if a["rel"] == "canonical" {
					p.Canonical = a["href"]
				} else if a["href"] != "" {
					p.Loads = append(p.Loads, a["href"])
				}
			case "img", "source":
				if a["src"] != "" {
					p.Loads = append(p.Loads, a["src"])
				}
				// An image's text alternative is text a reader hears.
				text.WriteString(a["alt"] + " ")
				if inFooter {
					footer.WriteString(a["alt"] + " ")
				}
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c, inFooter, inHead)
		}
	}
	walk(doc, false, false)
	p.Text = collapse(text.String())
	p.FooterText = collapse(footer.String())
	return p, nil
}

func attrs(n *html.Node) map[string]string {
	m := map[string]string{}
	for _, a := range n.Attr {
		m[a.Key] = a.Val
	}
	return m
}

func innerText(n *html.Node) string {
	var b strings.Builder
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.TextNode {
			b.WriteString(n.Data)
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return b.String()
}

func collapse(s string) string { return strings.Join(strings.Fields(s), " ") }
