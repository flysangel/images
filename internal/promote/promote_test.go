package promote

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/go-containerregistry/pkg/name"
	ggcrreg "github.com/google/go-containerregistry/pkg/registry"
	"github.com/google/go-containerregistry/pkg/v1"
	"github.com/google/go-containerregistry/pkg/v1/random"
	"github.com/google/go-containerregistry/pkg/v1/remote"

	"github.com/flysangel/images/internal/registry"
)

func setup(t *testing.T) (string, registry.Client) {
	srv := httptest.NewServer(ggcrreg.New())
	t.Cleanup(srv.Close)
	return strings.TrimPrefix(srv.URL, "http://"), registry.New(remote.WithTransport(srv.Client().Transport))
}

func push(t *testing.T, ref string) v1.Image {
	img, err := random.Image(32, 1)
	if err != nil {
		t.Fatal(err)
	}
	tg, _ := name.NewTag(ref)
	if err := remote.Write(tg, img); err != nil {
		t.Fatal(err)
	}
	return img
}

func TestRefuseOverwrite(t *testing.T) {
	host, rc := setup(t)
	push(t, host+"/stg/alpine:sshd-abc")
	push(t, host+"/prod/alpine:sshd-1.0")
	before, _ := rc.Digest(host + "/prod/alpine:sshd-1.0")
	err := Promote(rc, host+"/stg/alpine:sshd-abc", host+"/prod/alpine:sshd-1.0")
	if err == nil || !strings.Contains(err.Error(), "sshd-1.0 已存在，拒絕覆蓋") {
		t.Fatalf("err = %v", err)
	}
	after, _ := rc.Digest(host + "/prod/alpine:sshd-1.0")
	if before != after {
		t.Errorf("目的 digest 被改了：%s → %s", before, after)
	}
}

func TestCopyKeepsDigest(t *testing.T) {
	host, rc := setup(t)
	img := push(t, host+"/stg/alpine:sshd-abc")
	d, _ := img.Digest()
	// from 用 ref@digest 的形式，與 CI 實際傳入的一致。
	if err := Promote(rc, host+"/stg/alpine@"+d.String(), host+"/prod/alpine:sshd-1.0"); err != nil {
		t.Fatal(err)
	}
	got, err := rc.Digest(host + "/prod/alpine:sshd-1.0")
	if err != nil || got != d.String() {
		t.Errorf("digest = %s, %v；want %s", got, err, d)
	}
}

// 部分成功後重跑：目的 tag 已存在且 digest 與來源相同，視為成功。
func TestSkipWhenSameDigest(t *testing.T) {
	host, rc := setup(t)
	img := push(t, host+"/stg/alpine:sshd-abc")
	d, _ := img.Digest()
	from := host + "/stg/alpine@" + d.String()
	to := host + "/prod/alpine:sshd-1.0"
	if err := Promote(rc, from, to); err != nil {
		t.Fatal(err)
	}
	if err := Promote(rc, from, to); err != nil {
		t.Fatalf("同 digest 重跑應成功：%v", err)
	}
}
