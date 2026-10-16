package httpapi

import "net/http"

// appleCallback relays Apple's form_post to the Android app, which then
// posts the id_token to /v1/sessions/provider, where it is verified. The
// relay trusts nothing it carries: the target comes from configuration
// and the fields are only re-encoded. It is a form post
// from appleid.apple.com, so it skips the JSON and CSRF checks.
func (s *Server) appleCallback(w http.ResponseWriter, r *http.Request) {
	if s.AppleAndroidPackage == "" {
		writeProblem(w, newProblem(http.StatusNotFound, "not_found"))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	if err := r.ParseForm(); err != nil {
		s.fail(w, errBadBody)
		return
	}
	target := "intent://callback?" + r.PostForm.Encode() +
		"#Intent;package=" + s.AppleAndroidPackage + ";scheme=signinwithapple;end"
	w.Header().Set("Location", target)
	w.WriteHeader(http.StatusSeeOther)
}
