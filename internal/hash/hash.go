// Package hash 算節點的輸入雜湊：輸入沒變，映像就不必重建。
package hash

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/dockerfile"
	"github.com/flysangel/images/internal/graph"
)

// Input 回傳 n 的輸入雜湊（sha256 hex）。內容依序為：
// Dockerfile 位元組、BuildArgs（鍵排序）、上游 digest、本地上層的 Input（遞迴）、
// infra/<family>/ 整個 build context 的相對路徑與內容（路徑排序）。
// 上層用雜湊而非 digest：上層同一次 pipeline 才建，plan 時還沒有 digest。
func Input(cat *catalog.Catalog, g *graph.Graph, n graph.Node, overrides map[string]string) (string, error) {
	file := g.File(n)
	if file == nil {
		return "", fmt.Errorf("圖裡沒有節點 %s", n)
	}
	h := sha256.New()
	section := func(name string, body []byte) {
		fmt.Fprintf(h, "%s %d\n", name, len(body))
		h.Write(body)
		h.Write([]byte("\n"))
	}

	df, err := os.ReadFile(file.Path)
	if err != nil {
		return "", err
	}
	section("dockerfile", df)

	args, err := cat.BuildArgs(n.Family, n.Service, declared(file.ArgDecls), overrides)
	if err != nil {
		return "", err
	}
	keys := make([]string, 0, len(args))
	for k := range args {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var sb strings.Builder
	for _, k := range keys {
		fmt.Fprintf(&sb, "%s=%s\n", k, args[k])
	}
	section("args", []byte(sb.String()))

	local, upstream := g.Parents(n)
	sb.Reset()
	for _, u := range upstream {
		fmt.Fprintf(&sb, "%s=%s\n", u, cat.Upstream[u].Digest)
	}
	section("upstream", []byte(sb.String()))

	sb.Reset()
	for _, p := range local {
		ph, err := Input(cat, g, p, overrides)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(&sb, "%s=%s\n", p, ph)
	}
	section("parents", []byte(sb.String()))

	ctx := filepath.Join(g.Root, "infra", n.Family)
	var paths []string
	err = filepath.WalkDir(ctx, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() {
			paths = append(paths, p)
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	sort.Strings(paths)
	for _, p := range paths {
		body, err := os.ReadFile(p)
		if err != nil {
			return "", err
		}
		rel, _ := filepath.Rel(ctx, p)
		section("file:"+filepath.ToSlash(rel), body)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// declared 回傳光桿 ARG 名（去重，排除 *_IMAGE）。
func declared(decls []dockerfile.ArgDecl) []string {
	seen := map[string]bool{}
	var out []string
	for _, d := range decls {
		if d.HasDefault || strings.HasSuffix(d.Name, "_IMAGE") || seen[d.Name] {
			continue
		}
		seen[d.Name] = true
		out = append(out, d.Name)
	}
	return out
}
