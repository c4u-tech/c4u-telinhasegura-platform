package identity

import (
	"context"
	"errors"
)

// TermsVersion is the date of the terms of use and the privacy policy
// published on the site. A change that matters to users bumps it, and every
// account accepts the new version once.
const TermsVersion = "2026-10-21"

// ErrTermsOutdated means the version the client showed is not the current one.
var ErrTermsOutdated = errors.New("identity: terms version outdated")

func checkTerms(v string) error {
	switch {
	case v == "":
		return ErrValidation
	case v != TermsVersion:
		return ErrTermsOutdated
	}
	return nil
}

// AcceptTerms records that the account accepted the current terms.
func (s *Service) AcceptTerms(ctx context.Context, accountID, termsVersion string) error {
	if err := checkTerms(termsVersion); err != nil {
		return err
	}
	return s.d.Store.acceptTerms(ctx, accountID, termsVersion, s.d.Now())
}
