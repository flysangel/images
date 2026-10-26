package graph

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/flysangel/images/internal/catalog"
)

// batchNames 載入真的 catalog，只留 keep 這個 family，回傳分批後的 service 名。
func batchNames(t *testing.T, keep string) (*Graph, [][]string) {
	t.Helper()
	cat, err := catalog.Load("../../catalog.yaml")
	if err != nil {
		t.Fatal(err)
	}
	for name := range cat.Families {
		if name != keep {
			delete(cat.Families, name)
		}
	}
	g, err := Build(cat, "../..")
	if err != nil {
		t.Fatal(err)
	}
	batches, err := g.Batches()
	if err != nil {
		t.Fatal(err)
	}
	var got [][]string
	for _, b := range batches {
		var names []string
		for _, n := range b {
			names = append(names, n.Service)
		}
		got = append(got, names)
	}
	return g, got
}

func TestUbuntuBatches(t *testing.T) {
	g, got := batchNames(t, "ubuntu")
	want := [][]string{{"base"}, {"sshd"}, {"knife"}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Batches = %v，要 %v", got, want)
	}
	local, up := g.Parents(Node{"ubuntu", "knife"})
	if len(local) != 1 || local[0].String() != "ubuntu:sshd" || len(up) != 0 {
		t.Errorf("knife Parents = %v、%v", local, up)
	}
	_, up = g.Parents(Node{"ubuntu", "base"})
	if len(up) != 1 || up[0] != "LIBRARY_UBUNTU" {
		t.Errorf("base 上游 = %v", up)
	}
}

func TestAlpineBatches(t *testing.T) {
	g, got := batchNames(t, "alpine")
	want := [][]string{{"base"}, {"runner", "sshd"}, {"podman", "qemu", "s3cli"}, {"k8stools"}, {"k8sadm"}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Batches = %v，要 %v", got, want)
	}
	local, up := g.Parents(Node{"alpine", "s3cli"})
	if len(local) != 1 || local[0].String() != "alpine:sshd" || len(up) != 1 || up[0] != "MINIO_MC" {
		t.Errorf("s3cli Parents = %v、%v", local, up)
	}
}

// 兩個 family 同載時：同名 service 不互相串線，批內同名時 family 字母序在前。
func TestAlpineUbuntuTogether(t *testing.T) {
	cat, err := catalog.Load("../../catalog.yaml")
	if err != nil {
		t.Fatal(err)
	}
	g, err := Build(cat, "../..")
	if err != nil {
		t.Fatal(err)
	}
	batches, err := g.Batches()
	if err != nil {
		t.Fatal(err)
	}
	var first []Node
	for _, b := range batches {
		hasA, hasU := false, false
		for _, n := range b {
			hasA = hasA || n == Node{"alpine", "base"}
			hasU = hasU || n == Node{"ubuntu", "base"}
		}
		if hasA && hasU {
			first = b
			break
		}
	}
	if len(first) < 2 || first[0] != (Node{"alpine", "base"}) || first[1] != (Node{"ubuntu", "base"}) {
		t.Errorf("同批應為 alpine:base 在 ubuntu:base 前：%v", first)
	}
	for _, c := range []struct{ node, want Node }{
		{Node{"ubuntu", "sshd"}, Node{"ubuntu", "base"}},
		{Node{"alpine", "sshd"}, Node{"alpine", "base"}},
	} {
		local, _ := g.Parents(c.node)
		if len(local) != 1 || local[0] != c.want {
			t.Errorf("%s Parents = %v，要只有 %s", c.node, local, c.want)
		}
	}
}

func TestCycle(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "infra", "loop")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("a.Dockerfile", "ARG LOOP_B_IMAGE\nFROM ${LOOP_B_IMAGE}\n")
	write("b.Dockerfile", "ARG LOOP_A_IMAGE\nFROM ${LOOP_A_IMAGE}\n")
	cat := &catalog.Catalog{Families: map[string]catalog.Family{
		"loop": {Services: map[string]catalog.Service{"a": {Class: "C"}, "b": {Class: "C"}}},
	}}
	g, err := Build(cat, root)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := g.Batches(); err == nil {
		t.Error("環狀依賴應回錯")
	}
}
