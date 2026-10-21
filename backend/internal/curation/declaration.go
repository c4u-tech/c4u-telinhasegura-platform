package curation

import (
	"context"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

// CuratorTermsVersion names the curator terms in force. A curator who has
// not accepted this version reviews nothing.
const CuratorTermsVersion = "2026-10-20"

// CuratorTermsText is what a curator promises, shown with its version.
const CuratorTermsText = "Ao fazer parte da curadoria, você se compromete a: aplicar os critérios publicados em " +
	"Como escolhemos os vídeos e responder à lista de perguntas a cada vídeo; não revisar " +
	"vídeos do seu próprio canal, de parentes, nem de empresas ou marcas com que você tenha " +
	"vínculo ou que te paguem; marcar 'tenho dúvida' sempre que não tiver certeza; avisar a " +
	"equipe e deixar a curadoria se surgir um conflito. A Coding4u pode rever suas decisões e " +
	"retirar você da curadoria."

// Declaration is the curator terms in force and whether the account
// accepted them.
type Declaration struct {
	Version  string
	Text     string
	Accepted bool
}

// Declared reports whether the account accepted the terms in force.
func (s *Service) Declared(ctx context.Context, accountID string) (bool, error) {
	var ok bool
	err := s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM curator_declarations
		WHERE account_id = $1::uuid AND version = $2)`, accountID, CuratorTermsVersion).Scan(&ok)
	return ok, err
}

// Declaration returns the terms in force and whether the account accepted them.
func (s *Service) Declaration(ctx context.Context, accountID string) (Declaration, error) {
	ok, err := s.Declared(ctx, accountID)
	return Declaration{Version: CuratorTermsVersion, Text: CuratorTermsText, Accepted: ok}, err
}

// AcceptDeclaration records the account's acceptance of version, once.
// Any version but the one in force is refused, so nobody is recorded as
// agreeing to words they were not shown.
func (s *Service) AcceptDeclaration(ctx context.Context, accountID, version string) (Declaration, error) {
	if version != CuratorTermsVersion {
		return Declaration{}, ErrDeclarationOutdated
	}
	tag, err := s.d.Pool.Exec(ctx, `INSERT INTO curator_declarations (account_id, version, accepted_at)
		VALUES ($1::uuid, $2, $3) ON CONFLICT (account_id, version) DO NOTHING`, accountID, version, s.now())
	if err != nil {
		return Declaration{}, err
	}
	if tag.RowsAffected() == 1 {
		s.d.Audit.Record(ctx, accountID, audit.CuratorTermsAccepted)
	}
	return Declaration{Version: version, Text: CuratorTermsText, Accepted: true}, nil
}

// declarationRetentionYears is how long an acceptance of the curator
// terms is kept: as long as the security record, to answer for a
// curator's decisions in a dispute.
const declarationRetentionYears = 5

// SweepDeclarations deletes the acceptances older than five years, except
// a current curator's acceptance of the terms in force: their reviews
// rest on it, and deleting it would lock them out. It is idempotent, so
// every replica may run it.
func (s *Service) SweepDeclarations(ctx context.Context) error {
	_, err := s.d.Pool.Exec(ctx, `DELETE FROM curator_declarations d WHERE d.accepted_at < $1
		AND NOT (d.version = $2 AND EXISTS (SELECT 1 FROM platform_roles p WHERE p.account_id = d.account_id AND p.role = 'curator'))`,
		s.now().AddDate(-declarationRetentionYears, 0, 0), CuratorTermsVersion)
	return err
}
