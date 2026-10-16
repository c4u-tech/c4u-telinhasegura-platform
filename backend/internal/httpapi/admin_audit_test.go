package httpapi_test

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
)

type auditPageResp struct {
	Actions []struct {
		ID                 int64             `json:"id"`
		OccurredAt         string            `json:"occurred_at"`
		Event              string            `json:"event"`
		ActorID            string            `json:"actor_id"`
		ActorEmail         *string           `json:"actor_email"`
		ActorRole          string            `json:"actor_role"`
		SubjectKind        *string           `json:"subject_kind"`
		SubjectID          *string           `json:"subject_id"`
		SubjectEmailMasked *string           `json:"subject_email_masked"`
		Reason             *string           `json:"reason"`
		Metadata           map[string]string `json:"metadata"`
	} `json:"actions"`
	NextOffset *int `json:"next_offset"`
}

// seedLookups writes n lookups of subject by actor straight to the
// database, a second apart from now, reasons "Pedido 1." to "Pedido n.":
// this fixture's recorder keeps audit actions in memory.
func (a *api) seedLookups(actor, subject string, n int) {
	a.t.Helper()
	if _, err := a.pool.Exec(context.Background(), `INSERT INTO audit_events
		(account_id, event, occurred_at, actor_role, subject_kind, subject_id, reason, metadata)
		SELECT $1::uuid, 'account_looked_up', $3::timestamptz + n * interval '1 second', 'admin', 'account', $2::uuid,
			'Pedido ' || n || '.', '{"by": "email"}'
		FROM generate_series(1, $4::int) AS n`, actor, subject, a.now, n); err != nil {
		a.t.Fatal(err)
	}
}

func TestAuditLogOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	anaID := a.accountID(admin)
	a.signUpVerified("bia@example.com")
	biaID := a.accountID(a.signInMobile("bia@example.com"))
	a.seedLookups(anaID, biaID, 51)
	if _, err := a.pool.Exec(context.Background(), `INSERT INTO audit_events (account_id, event, occurred_at)
		VALUES ($1::uuid, 'sign_in_succeeded', $2::timestamptz + interval '1 hour')`, biaID, a.now); err != nil {
		t.Fatal(err)
	}

	var page auditPageResp
	getJSON(t, a.do(http.MethodGet, "/v1/admin/audit", nil, bearer(admin)...), &page)
	if len(page.Actions) != 50 || page.NextOffset == nil || *page.NextOffset != 50 {
		t.Fatalf("first page: %d actions, next %v", len(page.Actions), page.NextOffset)
	}
	first := page.Actions[0]
	if first.Event != "account_looked_up" || first.ActorID != anaID || first.ActorEmail == nil || *first.ActorEmail != "ana@example.com" ||
		first.ActorRole != "admin" || first.SubjectKind == nil || *first.SubjectKind != "account" || first.SubjectID == nil ||
		*first.SubjectID != biaID || first.SubjectEmailMasked == nil || *first.SubjectEmailMasked != "b•••@e•••.com" ||
		first.Reason == nil || *first.Reason != "Pedido 51." || first.Metadata["by"] != "email" || first.ID == 0 {
		t.Fatalf("newest action %+v", first)
	}
	r := a.do(http.MethodGet, "/v1/admin/audit?offset=50", nil, bearer(admin)...)
	page = auditPageResp{}
	getJSON(t, r, &page)
	if len(page.Actions) != 1 || page.NextOffset != nil || *page.Actions[0].Reason != "Pedido 1." ||
		!strings.Contains(r.Body.String(), `"next_offset":null`) {
		t.Fatalf("last page %s", r.Body)
	}
	for _, bad := range []string{"abc", "-1"} {
		if r := a.do(http.MethodGet, "/v1/admin/audit?offset="+bad, nil, bearer(admin)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
			t.Errorf("offset %q: %d %q", bad, r.Code, r.problemCode())
		}
	}
}

func TestErasedSubjectLeavesTheLogWithoutReasonOrEmail(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	anaID := a.accountID(admin)
	a.signUpVerified("bia@example.com")
	biaID := a.accountID(a.signInMobile("bia@example.com"))
	a.seedLookups(anaID, biaID, 2)
	if err := a.server.Privacy.DeleteAccount(context.Background(), biaID, nil); err != nil {
		t.Fatal(err)
	}
	r := a.do(http.MethodGet, "/v1/admin/audit", nil, bearer(admin)...)
	var page auditPageResp
	getJSON(t, r, &page)
	if len(page.Actions) != 2 {
		t.Fatalf("actions %s", r.Body)
	}
	for _, x := range page.Actions {
		if x.SubjectID == nil || *x.SubjectID != biaID || x.Reason != nil || x.SubjectEmailMasked != nil ||
			x.ActorEmail == nil || *x.ActorEmail != "ana@example.com" {
			t.Fatalf("after the erasure the action keeps its ids only: %+v", x)
		}
	}
	if strings.Contains(r.Body.String(), "Pedido") {
		t.Fatalf("a reason about the erased account is still answered: %s", r.Body)
	}
}

func TestMetricsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	r := a.do(http.MethodGet, "/v1/admin/metrics", nil, bearer(admin)...)
	if r.Code != http.StatusOK {
		t.Fatalf("metrics: %d %s", r.Code, r.Body)
	}
	for _, key := range []string{`"accounts":null`, `"families":null`, `"minors":null`, `"active_devices":null`,
		`"published_videos":null`, `"published_packs":null`, `"reports_7d":null`, `"suppressed_below":5`} {
		if !strings.Contains(r.Body.String(), key) {
			t.Errorf("missing %s in %s", key, r.Body)
		}
	}
	for i := range 4 {
		a.signUpVerified(fmt.Sprintf("p%d@example.com", i))
	}
	var m struct {
		Accounts *int `json:"accounts"`
		Families *int `json:"families"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/admin/metrics", nil, bearer(admin)...), &m)
	if m.Accounts == nil || *m.Accounts != 5 || m.Families != nil {
		t.Fatalf("five accounts and no family: %+v", m)
	}
}
