package curation_test

import (
	"errors"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

const curatorTerms = "Ao fazer parte da curadoria, você se compromete a: aplicar os critérios publicados em " +
	"Como escolhemos os vídeos e responder à lista de perguntas a cada vídeo; não revisar " +
	"vídeos do seu próprio canal, de parentes, nem de empresas ou marcas com que você tenha " +
	"vínculo ou que te paguem; marcar 'tenho dúvida' sempre que não tiver certeza; avisar a " +
	"equipe e deixar a curadoria se surgir um conflito. A Coding4u pode rever suas decisões e " +
	"retirar você da curadoria."

func TestCuratorDeclaration(t *testing.T) {
	f := newFixture(t)
	c := f.curator("bia@example.com", curation.MaePai)
	d, err := f.svc.Declaration(ctx, c)
	if err != nil || d.Version != "2026-10-20" || d.Text != curatorTerms || d.Accepted {
		t.Fatalf("declaration %+v %v", d, err)
	}
	// An older version accepted earlier does not count.
	f.exec(`INSERT INTO curator_declarations (account_id, version, accepted_at) VALUES ($1::uuid, '2026-01-01', $2)`, c, f.now)
	if ok, err := f.svc.Declared(ctx, c); err != nil || ok {
		t.Fatalf("an older version counted: %v %v", ok, err)
	}
	if _, err := f.svc.AcceptDeclaration(ctx, c, "2026-01-01"); !errors.Is(err, curation.ErrDeclarationOutdated) {
		t.Fatalf("an old version: %v", err)
	}
	for range 2 {
		if d, err = f.svc.AcceptDeclaration(ctx, c, curation.CuratorTermsVersion); err != nil || !d.Accepted || d.Text != curatorTerms {
			t.Fatalf("accept: %+v %v", d, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM curator_declarations WHERE account_id = $1::uuid AND version = '2026-10-20'
		AND accepted_at = $2`, c, f.now); n != 1 {
		t.Fatalf("acceptances stored: %d", n)
	}
	if n := f.audited(audit.CuratorTermsAccepted); n != 1 {
		t.Fatalf("curator_terms_accepted recorded %d times", n)
	}
	if ok, err := f.svc.Declared(ctx, c); err != nil || !ok {
		t.Fatalf("declared: %v %v", ok, err)
	}
	// The proof outlives the role.
	f.exec(`DELETE FROM platform_roles WHERE account_id = $1::uuid`, c)
	if n := f.count(`SELECT count(*) FROM curator_declarations WHERE account_id = $1::uuid`, c); n != 2 {
		t.Fatalf("declarations after the role went: %d", n)
	}
}
