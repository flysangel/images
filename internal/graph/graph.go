// Package graph 從 Dockerfile 的 FROM ${X_IMAGE} 建出 service 之間的依賴圖。
package graph

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/dockerfile"
)

// Node 是 catalog 裡的一個 service。
type Node struct {
	Family, Service string
}

func (n Node) String() string { return n.Family + ":" + n.Service }

// Graph 記錄每個節點的 Dockerfile 與上層。
type Graph struct {
	Root  string // repo 根
	files map[Node]*dockerfile.File
	local map[Node][]Node
	up    map[Node][]string
}

// Build 解析 catalog 每個 service 的 infra/<family>/<service>.Dockerfile。
// FROM 的 ARG 名若等於某個 service 的 ImageArgName，該 service 是本地上層；
// 否則去掉 _IMAGE 後綴，當成 catalog upstream 的鍵。
func Build(cat *catalog.Catalog, repoRoot string) (*Graph, error) {
	g := &Graph{Root: repoRoot, files: map[Node]*dockerfile.File{}, local: map[Node][]Node{}, up: map[Node][]string{}}
	byArg := map[string]Node{}
	for fam, f := range cat.Families {
		for svc := range f.Services {
			byArg[dockerfile.ImageArgName(fam, svc)] = Node{fam, svc}
		}
	}
	for fam, f := range cat.Families {
		for svc := range f.Services {
			n := Node{fam, svc}
			file, err := dockerfile.Parse(filepath.Join(repoRoot, "infra", fam, svc+".Dockerfile"))
			if err != nil {
				return nil, err
			}
			g.files[n] = file
			for _, st := range file.Stages {
				if st.FromArg == "" {
					continue
				}
				if p, ok := byArg[st.FromArg]; ok {
					g.local[n] = appendUniq(g.local[n], p)
					continue
				}
				key, ok := strings.CutSuffix(st.FromArg, "_IMAGE")
				if !ok {
					return nil, fmt.Errorf("%s：FROM ${%s} 不是 *_IMAGE", file.Path, st.FromArg)
				}
				if _, ok := cat.Upstream[key]; !ok {
					return nil, fmt.Errorf("%s：FROM ${%s} 對不到 service 或 catalog upstream %s", file.Path, st.FromArg, key)
				}
				g.up[n] = appendUniq(g.up[n], key)
			}
			sort.Slice(g.local[n], func(i, j int) bool { return g.local[n][i].String() < g.local[n][j].String() })
			sort.Strings(g.up[n])
		}
	}
	return g, nil
}

func appendUniq[T comparable](s []T, v T) []T {
	for _, x := range s {
		if x == v {
			return s
		}
	}
	return append(s, v)
}

// File 回傳節點解析後的 Dockerfile。
func (g *Graph) File(n Node) *dockerfile.File { return g.files[n] }

// Parents 回傳本地上層節點與上游 catalog 鍵。
func (g *Graph) Parents(n Node) (local []Node, upstream []string) {
	return g.local[n], g.up[n]
}

// Batches 把節點分層：同一批的節點彼此獨立，上層都在更前面的批。每批依 Service 名排序。有環回錯。
func (g *Graph) Batches() ([][]Node, error) {
	left := map[Node]bool{}
	for n := range g.files {
		left[n] = true
	}
	var out [][]Node
	for len(left) > 0 {
		var batch []Node
		for n := range left {
			ready := true
			for _, p := range g.local[n] {
				if left[p] {
					ready = false
					break
				}
			}
			if ready {
				batch = append(batch, n)
			}
		}
		if len(batch) == 0 {
			var names []string
			for n := range left {
				names = append(names, n.String())
			}
			sort.Strings(names)
			return nil, fmt.Errorf("依賴有環：%s", strings.Join(names, "、"))
		}
		sort.Slice(batch, func(i, j int) bool {
			if batch[i].Service != batch[j].Service {
				return batch[i].Service < batch[j].Service
			}
			return batch[i].Family < batch[j].Family
		})
		for _, n := range batch {
			delete(left, n)
		}
		out = append(out, batch)
	}
	return out, nil
}
