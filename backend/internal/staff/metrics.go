package staff

import (
	"context"
	"time"
)

// SuppressedBelow is the smallest count the metrics answer; a smaller
// one is nil (null), so a total cannot single a family out. Every count is suppressed alike.
const SuppressedBelow = 5

const reportWindow = 7 * 24 * time.Hour

// Metrics are the platform totals; nil means 0-4.
type Metrics struct {
	Accounts        *int
	Families        *int
	Minors          *int
	ActiveDevices   *int // seen within 180 days
	PublishedVideos *int
	PublishedPacks  *int
	Reports7d       *int
}

// Metrics reads every total through its module. Reading them is not
// audited and needs no reason.
func (s *Service) Metrics(ctx context.Context) (Metrics, error) {
	var m Metrics
	since := s.now().Add(-reportWindow)
	for _, c := range []struct {
		dst   **int
		count func(context.Context) (int, error)
	}{
		{&m.Accounts, s.d.Accounts.CountAccounts},
		{&m.Families, s.d.Families.CountFamilies},
		{&m.Minors, s.d.Families.CountMinors},
		{&m.ActiveDevices, s.d.Devices.CountActiveDevices},
		{&m.PublishedVideos, s.d.Content.CountPublishedVideos},
		{&m.PublishedPacks, s.d.Content.CountPublishedPacks},
		{&m.Reports7d, func(ctx context.Context) (int, error) { return s.d.Content.CountReportsSince(ctx, since) }},
	} {
		n, err := c.count(ctx)
		if err != nil {
			return Metrics{}, err
		}
		*c.dst = suppress(n)
	}
	return m, nil
}

func suppress(n int) *int {
	if n < SuppressedBelow {
		return nil
	}
	return &n
}
