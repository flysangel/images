package graph

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/flysangel/images/internal/catalog"
)

func TestAlpineBatches(t *testing.T) {
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
	var got [][]string
	for _, b := range batches {
		var names []string
		for _, n := range b {
			names = append(names, n.Service)
		}
		got = append(got, names)
	}
	want := [][]string{{"base"}, {"runner", "sshd"}, {"podman", "qemu", "s3cli"}, {"k8stools"}, {"k8sadm"}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Batches = %v，要 %v", got, want)
	}
	local, up := g.Parents(Node{"alpine", "s3cli"})
	if len(local) != 1 || local[0].String() != "alpine:sshd" || len(up) != 1 || up[0] != "MINIO_MC" {
		t.Errorf("s3cli Parents = %v、%v", local, up)
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
