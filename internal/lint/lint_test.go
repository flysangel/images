package lint

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/flysangel/images/internal/catalog"
)

func testCatalog() *catalog.Catalog {
	return &catalog.Catalog{
		Upstream: map[string]catalog.Upstream{"LIBRARY_ALPINE": {Ref: "r", Digest: "sha256:x"}},
		Families: map[string]catalog.Family{"alpine": {
			Values:  map[string]string{"BASE": "3.21.3"},
			Aliases: map[string]string{"PROVISION_REF_IN": "PROVISION_REF"},
			Services: map[string]catalog.Service{
				"base": {Class: "A", Version: "3.21.3"},
				"sshd": {Class: "C"},
			},
		}},
		ProvisionRef: "v2.0.0",
	}
}

const goodBase = "ARG LIBRARY_ALPINE_IMAGE\nFROM ${LIBRARY_ALPINE_IMAGE}\nARG PROVISION_REF_IN\nENV PROVISION_REF=${PROVISION_REF_IN}\n"
const goodSshd = "ARG ALPINE_BASE_IMAGE\nFROM ${ALPINE_BASE_IMAGE}\n"

// setup 建出暫存 repo：infra/alpine/.imgctl 加上給定的 Dockerfile。
func setup(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, "infra", "alpine")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".imgctl"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

// expect 斷言恰有一個 Finding，指向 file:line 且訊息含 kw。
func expect(t *testing.T, fs []Finding, file string, line int, kw string) {
	t.Helper()
	if len(fs) != 1 {
		t.Fatalf("Finding 數 = %d，要 1：%v", len(fs), fs)
	}
	f := fs[0]
	if f.File != file || f.Line != line || !strings.Contains(f.Msg, kw) {
		t.Errorf("Finding = %+v，要 %s:%d 且訊息含 %q", f, file, line, kw)
	}
}

func TestValid(t *testing.T) {
	root := setup(t, map[string]string{"base.Dockerfile": goodBase, "sshd.Dockerfile": goodSshd})
	if fs := Run(testCatalog(), root); len(fs) != 0 {
		t.Errorf("合法 fixture 不該有 Finding：%v", fs)
	}
}

func TestRule1FromMustBeImageArg(t *testing.T) {
	root := setup(t, map[string]string{
		"base.Dockerfile": goodBase,
		"sshd.Dockerfile": "FROM alpine:3.21\n",
	})
	expect(t, Run(testCatalog(), root), "infra/alpine/sshd.Dockerfile", 1, "${X_IMAGE}")
}

func TestRule1UnknownImage(t *testing.T) {
	root := setup(t, map[string]string{
		"base.Dockerfile": goodBase,
		"sshd.Dockerfile": "ARG ALPINE_NOPE_IMAGE\nFROM ${ALPINE_NOPE_IMAGE}\n",
	})
	expect(t, Run(testCatalog(), root), "infra/alpine/sshd.Dockerfile", 2, "ALPINE_NOPE_IMAGE")
}

func TestRule2BareArgUnresolvable(t *testing.T) {
	root := setup(t, map[string]string{
		"base.Dockerfile": goodBase,
		"sshd.Dockerfile": goodSshd + "ARG NO_SUCH_KEY\nRUN echo ${NO_SUCH_KEY}\n",
	})
	expect(t, Run(testCatalog(), root), "infra/alpine/sshd.Dockerfile", 3, "NO_SUCH_KEY")
}

func TestRule3StageMustRedeclare(t *testing.T) {
	root := setup(t, map[string]string{
		"base.Dockerfile": goodBase,
		"sshd.Dockerfile": "ARG ALPINE_BASE_IMAGE\nARG BASE\nFROM ${ALPINE_BASE_IMAGE}\nRUN echo ${BASE}\n",
	})
	expect(t, Run(testCatalog(), root), "infra/alpine/sshd.Dockerfile", 3, "BASE")
}

func TestRule4ArgEnvSameName(t *testing.T) {
	root := setup(t, map[string]string{
		"base.Dockerfile": goodBase,
		"sshd.Dockerfile": goodSshd + "ARG BASE\nENV BASE=1\n",
	})
	expect(t, Run(testCatalog(), root), "infra/alpine/sshd.Dockerfile", 4, "BASE")
}

func TestRule5HadolintIgnoreBeforeArg(t *testing.T) {
	root := setup(t, map[string]string{
		"base.Dockerfile": goodBase,
		"sshd.Dockerfile": "# hadolint ignore=DL3006\nARG ALPINE_BASE_IMAGE\nFROM ${ALPINE_BASE_IMAGE}\n",
	})
	expect(t, Run(testCatalog(), root), "infra/alpine/sshd.Dockerfile", 2, "hadolint")
}

func TestRule6ServiceDockerfileMismatch(t *testing.T) {
	root := setup(t, map[string]string{
		"base.Dockerfile":  goodBase,
		"extra.Dockerfile": goodSshd,
	})
	fs := Run(testCatalog(), root)
	if len(fs) != 2 {
		t.Fatalf("Finding 數 = %d，要 2：%v", len(fs), fs)
	}
	joined := fs[0].File + fs[1].File
	if !strings.Contains(joined, "sshd.Dockerfile") || !strings.Contains(joined, "extra.Dockerfile") {
		t.Errorf("應指出缺 sshd 與多出 extra：%v", fs)
	}
}

func TestFindingString(t *testing.T) {
	if got := (Finding{File: "a/b", Line: 3, Msg: "x"}).String(); got != "a/b:3: x" {
		t.Errorf("String() = %q", got)
	}
}
