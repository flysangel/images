package registry

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/go-containerregistry/pkg/name"
	ggcrreg "github.com/google/go-containerregistry/pkg/registry"
	"github.com/google/go-containerregistry/pkg/v1/mutate"
	"github.com/google/go-containerregistry/pkg/v1/random"
	"github.com/google/go-containerregistry/pkg/v1/remote"
)

func TestRegistry(t *testing.T) {
	srv := httptest.NewServer(ggcrreg.New())
	defer srv.Close()
	host := strings.TrimPrefix(srv.URL, "http://")

	img, err := random.Image(64, 1)
	if err != nil {
		t.Fatal(err)
	}
	cf, _ := img.ConfigFile()
	cf.Config.Labels = map[string]string{"org.flysangel.input-hash": "abc"}
	img, err = mutate.ConfigFile(img, cf)
	if err != nil {
		t.Fatal(err)
	}
	ref := host + "/fam/svc:svc-1.0"
	tag, _ := name.NewTag(ref)
	if err := remote.Write(tag, img); err != nil {
		t.Fatal(err)
	}

	c := New(remote.WithTransport(srv.Client().Transport))

	tags, err := c.ListTags(host + "/fam/svc")
	if err != nil || len(tags) != 1 || tags[0] != "svc-1.0" {
		t.Fatalf("ListTags = %v, %v", tags, err)
	}
	if v, err := c.Label(ref, "org.flysangel.input-hash"); err != nil || v != "abc" {
		t.Errorf("Label = %q, %v", v, err)
	}
	if v, _ := c.Label(ref, "nope"); v != "" {
		t.Errorf("不存在的 label 應回空字串：%q", v)
	}
	if ok, err := c.Exists(ref); err != nil || !ok {
		t.Errorf("Exists = %v, %v", ok, err)
	}
	if ok, err := c.Exists(host + "/fam/svc:missing"); err != nil || ok {
		t.Errorf("不存在的 tag：Exists = %v, %v", ok, err)
	}
	dst := host + "/other/svc:copy"
	if err := c.Copy(ref, dst); err != nil {
		t.Fatal(err)
	}
	d1, err1 := c.Digest(ref)
	d2, err2 := c.Digest(dst)
	if err1 != nil || err2 != nil || d1 != d2 || !strings.HasPrefix(d1, "sha256:") {
		t.Errorf("digest 不同：%s、%s（%v、%v）", d1, d2, err1, err2)
	}
}
