package plan

import (
	"strings"
	"testing"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/graph"
	"github.com/flysangel/images/internal/hash"
)

const labelKey = "org.flysangel.input-hash"

// fakeRegistry 以 repo → tag → input-hash label 模擬 quay。
type fakeRegistry struct {
	tags map[string]map[string]string
}

func (f *fakeRegistry) ListTags(repo string) ([]string, error) {
	var out []string
	for t := range f.tags[repo] {
		out = append(out, t)
	}
	return out, nil
}

func (f *fakeRegistry) Label(ref, key string) (string, error) {
	i := strings.LastIndex(ref, ":")
	return f.tags[ref[:i]][ref[i+1:]], nil
}

func (f *fakeRegistry) Digest(string) (string, error) { return "", nil }
func (f *fakeRegistry) Copy(string, string) error     { return nil }
func (f *fakeRegistry) Exists(string) (bool, error)   { return true, nil }

func load(t *testing.T) (*catalog.Catalog, *graph.Graph) {
	t.Helper()
	cat, err := catalog.Load("../../catalog.yaml")
	if err != nil {
		t.Fatal(err)
	}
	// 這組測試以 alpine 的 8 個 service 為準。只留 alpine 是測試替身的限制：本檔的 items() 以 service 名為鍵，多 family 會撞名；正式碼以 graph.Node（family 加 service）為鍵，不受影響。
	delete(cat.Families, "ubuntu")
	g, err := graph.Build(cat, "../..")
	if err != nil {
		t.Fatal(err)
	}
	return cat, g
}

// seed 為每個 service 放一個 tag；withLabel 為 true 時帶上目前的輸入雜湊。
func seed(t *testing.T, cat *catalog.Catalog, g *graph.Graph, tagOf func(svc string) string, withLabel bool) *fakeRegistry {
	t.Helper()
	f := &fakeRegistry{tags: map[string]map[string]string{}}
	batches, err := g.Batches()
	if err != nil {
		t.Fatal(err)
	}
	for _, b := range batches {
		for _, n := range b {
			repo := cat.Registry + "/" + n.Family
			if f.tags[repo] == nil {
				f.tags[repo] = map[string]string{}
			}
			h := ""
			if withLabel {
				if h, err = hash.Input(cat, g, n, nil); err != nil {
					t.Fatal(err)
				}
			}
			f.tags[repo][tagOf(n.Service)] = h
		}
	}
	return f
}

func v103(svc string) string { return svc + "-v1.0.3" }

func items(p *Plan) map[string]Item {
	m := map[string]Item{}
	for _, b := range p.Batches {
		for _, it := range b {
			m[it.Service] = it
		}
	}
	return m
}

func TestFirstRun(t *testing.T) {
	cat, g := load(t)
	p, err := Make(cat, g, seed(t, cat, g, v103, false), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	m := items(p)
	if len(m) != 8 {
		t.Fatalf("service 數 = %d", len(m))
	}
	for s, it := range m {
		if !it.Rebuild {
			t.Errorf("%s 應重建", s)
		}
	}
	want := map[string]string{"k8stools": "k8stools-v1.0.4", "k8sadm": "k8sadm-v1.0.4", "base": "base-3.21.3", "s3cli": "s3cli-4.36", "sshd": "", "podman": "", "qemu": "", "runner": ""}
	for s, w := range want {
		if m[s].Tag != w {
			t.Errorf("%s Tag = %q，預期 %q", s, m[s].Tag, w)
		}
	}
	if got := m["base"].Upstream["LIBRARY_ALPINE_IMAGE"]; got != "quay.io/flysangel/library/alpine@"+cat.Upstream["LIBRARY_ALPINE"].Digest {
		t.Errorf("base 的 Upstream = %q", got)
	}
	if m["sshd"].Class != "B" || m["sshd"].InputHash == "" || m["sshd"].BuildArgs == nil {
		t.Errorf("sshd 欄位不完整：%+v", m["sshd"])
	}
}

func TestNoChange(t *testing.T) {
	cat, g := load(t)
	p, err := Make(cat, g, seed(t, cat, g, v103, true), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	for s, it := range items(p) {
		if it.Rebuild {
			t.Errorf("%s 不應重建", s)
		}
		if it.Tag != s+"-v1.0.3" {
			t.Errorf("%s 應沿用既有 tag，得 %q", s, it.Tag)
		}
	}
}

func TestProvisionBump(t *testing.T) {
	cat, g := load(t)
	f := seed(t, cat, g, v103, true)
	p, err := Make(cat, g, f, map[string]string{"PROVISION_REF": "v2.1.0"}, false)
	if err != nil {
		t.Fatal(err)
	}
	m := items(p)
	for s, it := range m {
		if !it.Rebuild {
			t.Errorf("%s 應重建", s)
		}
	}
	if len(m) != 8 {
		t.Errorf("service 數 = %d", len(m))
	}
	if m["sshd"].Reason != "上層重建" && m["sshd"].Reason != "輸入改變" {
		t.Errorf("sshd Reason = %q", m["sshd"].Reason)
	}
}

func TestContextOnly(t *testing.T) {
	cat, g := load(t)
	f := seed(t, cat, g, v103, true)
	f.tags[cat.Registry+"/alpine"]["k8sadm-v1.0.3"] = "stale"
	p, err := Make(cat, g, f, nil, false)
	if err != nil {
		t.Fatal(err)
	}
	for s, it := range items(p) {
		if it.Rebuild != (s == "k8sadm") {
			t.Errorf("%s Rebuild = %v", s, it.Rebuild)
		}
	}
}

// 上層的 label 過期時，子層即使自己的 label 吻合也要跟著重建。
func TestParentRebuildPropagates(t *testing.T) {
	cat, g := load(t)
	f := seed(t, cat, g, v103, true)
	f.tags[cat.Registry+"/alpine"]["sshd-v1.0.3"] = "stale"
	p, err := Make(cat, g, f, nil, false)
	if err != nil {
		t.Fatal(err)
	}
	m := items(p)
	for _, s := range []string{"sshd", "podman", "qemu", "s3cli", "k8stools", "k8sadm"} {
		if !m[s].Rebuild {
			t.Errorf("%s 應重建", s)
		}
		if s != "sshd" && m[s].Reason != "上層重建" {
			t.Errorf("%s Reason = %q", s, m[s].Reason)
		}
	}
}
