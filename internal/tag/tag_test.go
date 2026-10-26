package tag

import "testing"

func TestSanitize(t *testing.T) {
	cases := []struct{ in, want string }{
		{"2.4+dfsg~1", "2.4_dfsg_1"},
		{"9.9_p1", "9.9_p1"},
		{"a b/c", "a_b_c"},
	}
	for _, c := range cases {
		if got := Sanitize(c.in); got != c.want {
			t.Errorf("Sanitize(%q)=%q，要 %q", c.in, got, c.want)
		}
	}
}

func TestParseVersionOutput(t *testing.T) {
	cases := []struct {
		kind, in, want string
		wantErr        bool
	}{
		{"apk", "openssh-server-9.9_p1-r3", "9.9_p1", false},
		{"apk", "  openssh-server-9.9_p1-r3\n", "9.9_p1", false},
		{"dpkg", "1:9.6p1-3ubuntu13", "9.6p1", false},
		{"dpkg", "2.4+dfsg~1-2", "2.4+dfsg~1", false},
		{"dpkg", "1.0-beta-2", "1.0-beta", false},
		{"command", "Task version: v3.54.0 (h1:abc)", "3.54.0", false},
		{"command", "no version here", "", true},
		{"apk", "", "", true},
		{"dpkg", "\n", "", true},
		{"unknown", "1.2.3", "", true},
	}
	for _, c := range cases {
		got, err := ParseVersionOutput(c.kind, c.in)
		if (err != nil) != c.wantErr {
			t.Errorf("%s %q：err=%v，wantErr=%v", c.kind, c.in, err, c.wantErr)
			continue
		}
		if got != c.want {
			t.Errorf("%s %q=%q，要 %q", c.kind, c.in, got, c.want)
		}
	}
}

func TestNext(t *testing.T) {
	cases := []struct {
		name            string
		class, svc, ver string
		existing        []string
		bump            bool
		want            string
		wantErr         bool
	}{
		{"A 無同版", "A", "base", "3.21.3", []string{"base-v1.0.3"}, false, "base-3.21.3", false},
		{"A 已有", "A", "base", "3.21.3", []string{"base-3.21.3"}, false, "base-3.21.3-r2", false},
		{"B 無同版", "B", "sshd", "9.9_p1", nil, false, "sshd-9.9_p1", false},
		{"B r2", "B", "sshd", "9.9_p1", []string{"sshd-9.9_p1"}, false, "sshd-9.9_p1-r2", false},
		{"B r3", "B", "sshd", "9.9_p1", []string{"sshd-9.9_p1", "sshd-9.9_p1-r2"}, false, "sshd-9.9_p1-r3", false},
		{"B 忽略他服務與他版", "B", "sshd", "9.9_p1",
			[]string{"sshd-9.9_p1", "sshd-9.8-r7", "other-9.9_p1-r5", "sshd-9.9_p1-rx"}, false, "sshd-9.9_p1-r2", false},
		{"B 無基底只有 r2", "B", "sshd", "9.9_p1", []string{"sshd-9.9_p1-r2"}, false, "sshd-9.9_p1-r3", false},
		{"C patch", "C", "k8sadm", "", []string{"k8sadm-v1.0.3", "k8sadm-v1.0.10"}, false, "k8sadm-v1.0.11", false},
		{"C minor", "C", "k8sadm", "", []string{"k8sadm-v1.0.3", "k8sadm-v1.0.10"}, true, "k8sadm-v1.1.0", false},
		{"C 忽略他服務", "C", "k8sadm", "", []string{"k8sadm-v1.0.3", "x-v9.9.9"}, false, "k8sadm-v1.0.4", false},
		{"C 無版號", "C", "k8sadm", "", nil, false, "", true},
		{"未知類別", "Z", "x", "1", nil, false, "", true},
	}
	for _, c := range cases {
		got, err := Next(c.class, c.svc, c.ver, c.existing, c.bump)
		if (err != nil) != c.wantErr {
			t.Errorf("%s：err=%v，wantErr=%v", c.name, err, c.wantErr)
			continue
		}
		if got != c.want {
			t.Errorf("%s：got %q，要 %q", c.name, got, c.want)
		}
	}
}
