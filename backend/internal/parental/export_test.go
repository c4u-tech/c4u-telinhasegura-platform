package parental

import "context"

// CheckPIN exposes checkPIN to the external tests.
func CheckPIN(ctx context.Context, s *Service, familyID, actorID, pin string) error {
	return s.checkPIN(ctx, familyID, actorID, pin)
}
