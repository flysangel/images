package build

import (
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/google/go-containerregistry/pkg/name"
	ggcrreg "github.com/google/go-containerregistry/pkg/registry"
	"github.com/google/go-containerregistry/pkg/v1/random"
	"github.com/google/go-containerregistry/pkg/v1/remote"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/plan"
	"github.com/flysangel/images/internal/registry"
)

var sshd = plan.Item{
	Family: "alpine", Service: "sshd", Class: "B", InputHash: "h123",
	BuildArgs: map[string]string{"PROVISION_REF_IN": "v2.0.0"},
	Upstream:  map[string]string{"LIBRARY_ALPINE_IMAGE": "quay.io/x/library/alpine@sha256:aa"},
	Parents:   []string{"alpine/base"},
}

func TestCommand(t *testing.T) {
	parent := "quay.io/flysangel/alpine@sha256:bb"
	got, err := Command(sshd, map[string]string{"ALPINE_BASE_IMAGE": parent}, "ghcr.io/flysangel/images-staging", "abc123")
	if err != nil {
		t.Fatal(err)
	}
	line := strings.Join(got, " ")
	for _, want := range []string{
		"podman build --format docker --label org.flysangel.input-hash=h123",
		"--build-arg ALPINE_BASE_IMAGE=" + parent,
		"--build-arg PROVISION_REF_IN=v2.0.0",
		"--build-arg LIBRARY_ALPINE_IMAGE=quay.io/x/library/alpine@sha256:aa",
		"--label org.flysangel.input-hash=h123",
		"-t ghcr.io/flysangel/images-staging/alpine:sshd-abc123",
		"-f infra/alpine/sshd.Dockerfile",
	} {
		if !strings.Contains(line, want) {
			t.Errorf("缺 %q\n%s", want, line)
		}
	}
	// --format docker 必要：OCI 格式會忽略 SHELL，pipefail 失效。
	if !slices.Contains(got, "--format") || strings.Contains(line, "buildx") ||
		strings.Contains(line, "--push") || strings.Contains(line, "--provenance") {
		t.Errorf("應為 podman build --format docker，不含 buildx/--push/--provenance：%s", line)
	}
	if got[len(got)-1] != "infra/alpine" {
		t.Errorf("最後一個參數應為 context：%v", got)
	}
}

func TestPushCommand(t *testing.T) {
	got := PushCommand("ghcr.io/x/alpine:sshd-abc", "/tmp/d")
	want := []string{"podman", "push", "--digestfile", "/tmp/d", "ghcr.io/x/alpine:sshd-abc"}
	if !slices.Equal(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestCommandMissingParent(t *testing.T) {
	_, err := Command(sshd, map[string]string{}, "ghcr.io/x", "abc")
	if err == nil || !strings.Contains(err.Error(), "ALPINE_BASE_IMAGE") {
		t.Errorf("缺 parent 應回錯並點名 ARG：%v", err)
	}
}

func TestProbeCommand(t *testing.T) {
	kind, argv, err := ProbeCommand("alpine", &catalog.VersionFrom{Package: "openssh-server"}, "img")
	if err != nil || kind != "apk" || !slices.Equal(argv, []string{"docker", "run", "--rm", "img", "apk", "info", "-e", "-v", "openssh-server"}) {
		t.Errorf("apk：%s %v %v", kind, argv, err)
	}
	kind, argv, err = ProbeCommand("ubuntu", &catalog.VersionFrom{Package: "git"}, "img")
	if err != nil || kind != "dpkg" || argv[len(argv)-1] != "git" {
		t.Errorf("dpkg：%s %v %v", kind, argv, err)
	}
	kind, argv, err = ProbeCommand("alpine", &catalog.VersionFrom{Command: "task --version"}, "img")
	if err != nil || kind != "command" || argv[len(argv)-1] != "task --version" {
		t.Errorf("command：%s %v %v", kind, argv, err)
	}
	if _, _, err = ProbeCommand("debian", &catalog.VersionFrom{Package: "git"}, "img"); err == nil {
		t.Error("未知 distro 應回錯")
	}
	if _, _, err = ProbeCommand("alpine", nil, "img"); err == nil {
		t.Error("沒有 version_from 應回錯")
	}
}

func TestResolveParents(t *testing.T) {
	srv := httptest.NewServer(ggcrreg.New())
	defer srv.Close()
	host := strings.TrimPrefix(srv.URL, "http://")
	img, _ := random.Image(32, 1)
	tg, _ := name.NewTag(host + "/fam/alpine:base-3.21.3")
	if err := remote.Write(tg, img); err != nil {
		t.Fatal(err)
	}
	dg, _ := img.Digest()
	rc := registry.New(remote.WithTransport(srv.Client().Transport))

	it := plan.Item{Family: "alpine", Service: "sshd", Parents: []string{"alpine/base"}}

	// 上層本輪沒重建：用 plan 的 tag 解析成 digest。
	p := &plan.Plan{Batches: [][]plan.Item{{{Family: "alpine", Service: "base", Tag: "base-3.21.3"}}}}
	got, err := ResolveParents(it, p, t.TempDir(), host+"/fam", rc)
	if err != nil {
		t.Fatal(err)
	}
	if want := host + "/fam/alpine@" + dg.String(); got["ALPINE_BASE_IMAGE"] != want {
		t.Errorf("got %v want %s", got, want)
	}

	// 上層本輪重建：目錄裡的 .ref 優先。
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "alpine_base.ref"), []byte("ghcr.io/s/alpine:base-1@sha256:cc\n"), 0o644)
	got, err = ResolveParents(it, p, dir, host+"/fam", rc)
	if err != nil || got["ALPINE_BASE_IMAGE"] != "ghcr.io/s/alpine:base-1@sha256:cc" {
		t.Errorf("ref 檔：%v %v", got, err)
	}

	// 上層本輪重建但 ref 檔沒到（例如 artifact 下載失敗）：不可退回查 registry。
	pr := &plan.Plan{Batches: [][]plan.Item{{{Family: "alpine", Service: "base", Tag: "base-3.21.3", Rebuild: true}}}}
	if _, err := ResolveParents(it, pr, t.TempDir(), host+"/fam", rc); err == nil || !strings.Contains(err.Error(), "alpine/base") {
		t.Errorf("重建的上層缺 ref 檔應回錯並點名上層：%v", err)
	}

	// 上層不在目錄、plan 也沒有可用 tag：回錯。
	p2 := &plan.Plan{Batches: [][]plan.Item{{{Family: "alpine", Service: "base"}}}}
	if _, err := ResolveParents(it, p2, t.TempDir(), host+"/fam", rc); err == nil {
		t.Error("沒有 tag 也沒有 ref 檔應回錯")
	}
}
