package registry

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/go-containerregistry/pkg/name"
	ggcrreg "github.com/google/go-containerregistry/pkg/registry"
	"github.com/google/go-containerregistry/pkg/v1/mutate"
	"github.com/google/go-containerregistry/pkg/v1/random"
	"github.com/google/go-containerregistry/pkg/v1/remote"
	"github.com/google/go-containerregistry/pkg/v1/remote/transport"
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

func TestListTagsUnknownRepo(t *testing.T) {
	srv := httptest.NewServer(ggcrreg.New())
	defer srv.Close()
	host := strings.TrimPrefix(srv.URL, "http://")
	c := New(remote.WithTransport(srv.Client().Transport))
	tags, err := c.ListTags(host + "/no/such")
	if err != nil || len(tags) != 0 {
		t.Errorf("ListTags = %v, %v", tags, err)
	}
}

// quay 對不存在的 repo 回 401 UNAUTHORIZED，要當成空清單；其他錯誤照報。
func TestListTags401(t *testing.T) {
	status := http.StatusUnauthorized
	code := "UNAUTHORIZED"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v2/" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(status)
		fmt.Fprintf(w, `{"errors":[{"code":%q,"message":"x"}]}`, code)
	}))
	defer srv.Close()
	host := strings.TrimPrefix(srv.URL, "http://")
	c := New(remote.WithTransport(srv.Client().Transport), remote.WithRetryBackoff(remote.Backoff{Duration: time.Millisecond, Factor: 1, Steps: 1}))
	if tags, err := c.ListTags(host + "/a/b"); err != nil || len(tags) != 0 {
		t.Errorf("401 UNAUTHORIZED：%v, %v", tags, err)
	}
	status, code = http.StatusInternalServerError, "UNKNOWN"
	if _, err := c.ListTags(host + "/a/b"); err == nil {
		t.Error("500 應回錯誤")
	}
}

// promote 靠 Exists 拒絕覆蓋：401 UNAUTHORIZED 不能當成「不存在」，否則會誤蓋既有 tag。
func TestExistsErrorsOn401(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v2/" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusUnauthorized)
		fmt.Fprint(w, `{"errors":[{"code":"UNAUTHORIZED","message":"x"}]}`)
	}))
	defer srv.Close()
	host := strings.TrimPrefix(srv.URL, "http://")
	c := New(remote.WithTransport(srv.Client().Transport), remote.WithRetryBackoff(remote.Backoff{Duration: time.Millisecond, Factor: 1, Steps: 1}))
	if ok, err := c.Exists(host + "/a/b:t"); err == nil || ok {
		t.Errorf("401 應回錯誤而不是 false：%v, %v", ok, err)
	}
}

// 直接餵 *transport.Error，鎖住嚴格版 isNotFound 與 ListTags 寬鬆版的邊界。
func TestNotFoundClassification(t *testing.T) {
	mk := func(status int, code transport.ErrorCode) error {
		return &transport.Error{StatusCode: status, Errors: []transport.Diagnostic{{Code: code}}}
	}
	cases := []struct {
		name            string
		err             error
		strict, lenient bool
	}{
		{"401 UNAUTHORIZED", mk(http.StatusUnauthorized, transport.UnauthorizedErrorCode), false, true},
		{"404 NAME_UNKNOWN", mk(http.StatusNotFound, transport.NameUnknownErrorCode), true, true},
		{"404 MANIFEST_UNKNOWN", mk(http.StatusNotFound, transport.ManifestUnknownErrorCode), true, true},
		{"500", mk(http.StatusInternalServerError, transport.UnsupportedErrorCode), false, false},
		{"非 transport 錯誤", fmt.Errorf("x"), false, false},
	}
	for _, c := range cases {
		if got := isNotFound(c.err); got != c.strict {
			t.Errorf("%s：isNotFound = %v，要 %v", c.name, got, c.strict)
		}
		if got := isNotFound(c.err) || isUnauthorizedNotFound(c.err); got != c.lenient {
			t.Errorf("%s：寬鬆版 = %v，要 %v", c.name, got, c.lenient)
		}
	}
}
