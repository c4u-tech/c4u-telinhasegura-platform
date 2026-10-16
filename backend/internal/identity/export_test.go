package identity

import "context"

// IssueEmailChange is RequestEmailChange's token write with the credential
// version its caller saw, so a test can make that version stale.
func IssueEmailChange(s *Service, ctx context.Context, accountID, sessionID, newEmail string, seen int64) error {
	_, err := s.issueChangeToken(ctx, accountID, sessionID, newEmail, seen)
	return err
}
