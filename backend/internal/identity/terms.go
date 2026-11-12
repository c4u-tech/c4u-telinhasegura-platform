package identity

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/legal"
)

// TermsVersion is the date of the terms of use and the privacy policy
// published on the site. A change that matters to users bumps it, and every
// account accepts the new version once.
const TermsVersion = "2026-11-11"

// PreviousTermsVersion is the version before TermsVersion. It still
// counts until the grace end the service is given, because the server
// changes before the app that shows the new terms reaches the stores: a
// family on the previous app has no update to install yet.
const PreviousTermsVersion = "2026-10-21"

// ErrTermsOutdated means the version the client showed is not the current one.
var ErrTermsOutdated = errors.New("identity: terms version outdated")

// terms is the terms in force with the grace the service was given.
func (s *Service) terms() legal.Version {
	return legal.Version{Current: TermsVersion, Previous: PreviousTermsVersion, GraceUntil: s.d.GraceUntil}
}

func (s *Service) checkTerms(v string) error {
	switch {
	case v == "":
		return ErrValidation
	case !s.terms().Accepts(v, s.d.Now()):
		return ErrTermsOutdated
	}
	return nil
}

// AcceptTerms records that the account accepted the terms, as sent.
func (s *Service) AcceptTerms(ctx context.Context, accountID, termsVersion string) error {
	if err := s.checkTerms(termsVersion); err != nil {
		return err
	}
	return s.d.Store.acceptTerms(ctx, accountID, termsVersion, s.d.Now())
}
