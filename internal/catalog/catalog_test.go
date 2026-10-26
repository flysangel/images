package catalog

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadValid(t *testing.T) {
	c, err := Load("testdata/valid.yaml")
	if err != nil {
		t.Fatal(err)
	}
	got := c.Families["alpine"].Services["sshd"].VersionFrom.Package
	if got != "openssh-server" {
		t.Fatalf("package = %q", got)
	}
}

func TestLoadUnknownKey(t *testing.T) {
	_, err := Load("testdata/typo.yaml")
	if err == nil || !strings.Contains(err.Error(), "families.alpine.services.sshd") {
		t.Fatalf("err = %v", err)
	}
}

func TestLoadClassRules(t *testing.T) {
	cases := map[string]struct{ from, to, want string }{
		"A缺version":      {`{ class: A, version: "3.21.3" }`, `{ class: A }`, "families.alpine.services.base.version"},
		"B缺version_from": {`{ class: B, version_from: { package: openssh-server } }`, `{ class: B }`, "families.alpine.services.sshd.version_from"},
		"二擇一":            {`{ package: openssh-server }`, `{ package: openssh-server, command: x }`, "families.alpine.services.sshd.version_from"},
		"digest":         {"sha256:aaaa", "md5:aaaa", "upstream.LIBRARY_ALPINE.digest"},
	}
	raw, err := os.ReadFile("testdata/valid.yaml")
	if err != nil {
		t.Fatal(err)
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			s := string(raw)
			if !strings.Contains(s, tc.from) {
				t.Fatalf("測試資料缺 %q", tc.from)
			}
			p := filepath.Join(t.TempDir(), "c.yaml")
			if err := os.WriteFile(p, []byte(strings.Replace(s, tc.from, tc.to, 1)), 0o644); err != nil {
				t.Fatal(err)
			}
			_, err := Load(p)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v，要含 %q", err, tc.want)
			}
		})
	}
}

func TestBuildArgsAlias(t *testing.T) {
	c, err := Load("testdata/valid.yaml")
	if err != nil {
		t.Fatal(err)
	}
	got, err := c.BuildArgs("alpine", "sshd", []string{"PROVISION_REF_IN", "BASE"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got["PROVISION_REF_IN"] != "v2.0.0" || got["BASE"] != "3.21.3" {
		t.Fatalf("got = %v", got)
	}
}

func TestBuildArgsMissing(t *testing.T) {
	c, err := Load("testdata/valid.yaml")
	if err != nil {
		t.Fatal(err)
	}
	_, err = c.BuildArgs("alpine", "sshd", []string{"NOPE"}, nil)
	if err == nil || !strings.Contains(err.Error(), "NOPE") {
		t.Fatalf("err = %v", err)
	}
}
