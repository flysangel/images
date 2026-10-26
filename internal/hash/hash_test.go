package hash

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/graph"
)

// fixture 建一個 base → app 的小 family，app 宣告 PROVISION_REF_IN，base 不宣告。
func fixture(t *testing.T) (string, *catalog.Catalog) {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, "infra", "fam")
	if err := os.MkdirAll(filepath.Join(dir, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"base.Dockerfile": "ARG LIBRARY_ALPINE_IMAGE\nFROM ${LIBRARY_ALPINE_IMAGE}\n",
		"app.Dockerfile":  "ARG FAM_BASE_IMAGE\nFROM ${FAM_BASE_IMAGE}\nARG PROVISION_REF_IN\nCOPY bin/ /bin/\n",
		"bin/entry.sh":    "echo hi\n",
	}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	cat := &catalog.Catalog{
		ProvisionRef: "v2.0.0",
		Upstream:     map[string]catalog.Upstream{"LIBRARY_ALPINE": {Ref: "x", Digest: "sha256:aa"}},
		Families: map[string]catalog.Family{"fam": {
			Aliases:  map[string]string{"PROVISION_REF_IN": "PROVISION_REF"},
			Services: map[string]catalog.Service{"base": {Class: "C"}, "app": {Class: "C"}},
		}},
	}
	return root, cat
}

func input(t *testing.T, root string, cat *catalog.Catalog, svc string, ov map[string]string) string {
	t.Helper()
	g, err := graph.Build(cat, root)
	if err != nil {
		t.Fatal(err)
	}
	h, err := Input(cat, g, graph.Node{Family: "fam", Service: svc}, ov)
	if err != nil {
		t.Fatal(err)
	}
	return h
}

func appendFile(t *testing.T, path, s string) {
	t.Helper()
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := f.WriteString(s); err != nil {
		t.Fatal(err)
	}
}

func TestStable(t *testing.T) {
	root, cat := fixture(t)
	if a, b := input(t, root, cat, "app", nil), input(t, root, cat, "app", nil); a != b {
		t.Errorf("同輸入兩次結果不同：%s、%s", a, b)
	}
}

func TestContextFileChanges(t *testing.T) {
	root, cat := fixture(t)
	before := input(t, root, cat, "app", nil)
	appendFile(t, filepath.Join(root, "infra/fam/bin/entry.sh"), "x")
	if before == input(t, root, cat, "app", nil) {
		t.Error("改 bin/entry.sh 後雜湊應改變")
	}
}

func TestParentPropagates(t *testing.T) {
	root, cat := fixture(t)
	before := input(t, root, cat, "app", nil)
	appendFile(t, filepath.Join(root, "infra/fam/base.Dockerfile"), "# c\n")
	if before == input(t, root, cat, "app", nil) {
		t.Error("改上層 Dockerfile 後子節點雜湊應改變")
	}
}

func TestOverride(t *testing.T) {
	root, cat := fixture(t)
	ov := map[string]string{"PROVISION_REF": "v2.1.0"}
	if input(t, root, cat, "app", nil) == input(t, root, cat, "app", ov) {
		t.Error("override PROVISION_REF 應改變 app 的雜湊")
	}
	if input(t, root, cat, "base", nil) != input(t, root, cat, "base", ov) {
		t.Error("base 不宣告 PROVISION_REF_IN，雜湊不應變")
	}
}
