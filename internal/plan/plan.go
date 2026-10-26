// Package plan 比對輸入雜湊與 registry 現況，決定每個 service 要不要重建。
package plan

import (
	"fmt"
	"sort"
	"strings"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/graph"
	"github.com/flysangel/images/internal/hash"
	"github.com/flysangel/images/internal/registry"
	"github.com/flysangel/images/internal/tag"
)

// HashLabel 是映像上記錄輸入雜湊的 label 鍵。
const HashLabel = "org.flysangel.input-hash"

// Plan 的 Batches 依依賴順序排列，同一批內互不相依。
type Plan struct {
	Batches [][]Item `json:"batches"`
}

// Item 是一個 service 的計畫。Tag 在乙類重建時為空（建完才知道版本）；
// 不重建時是 registry 上雜湊吻合的既有 tag。
type Item struct {
	Family    string            `json:"family"`
	Service   string            `json:"service"`
	Class     string            `json:"class"`
	InputHash string            `json:"input_hash"`
	Tag       string            `json:"tag"`
	Rebuild   bool              `json:"rebuild"`
	Reason    string            `json:"reason"`
	BuildArgs map[string]string `json:"build_args"`
	Upstream  map[string]string `json:"upstream"` // ARG 名 → ref@digest
}

// Make 算出整張圖的計畫。
// 判斷：同 service 在 registry 上的既有 tag（前綴 `<service>-`）中，
// 沒有任何一個的 input-hash label 等於算出的雜湊，就重建。不依賴 tag 排序。
func Make(cat *catalog.Catalog, g *graph.Graph, rc registry.Client, overrides map[string]string, bumpMinor bool) (*Plan, error) {
	batches, err := g.Batches()
	if err != nil {
		return nil, err
	}
	rebuilt := map[graph.Node]bool{}
	p := &Plan{}
	for _, batch := range batches {
		var out []Item
		for _, n := range batch {
			it, err := makeItem(cat, g, rc, n, overrides, bumpMinor, rebuilt)
			if err != nil {
				return nil, fmt.Errorf("%s：%w", n, err)
			}
			rebuilt[n] = it.Rebuild
			out = append(out, it)
		}
		p.Batches = append(p.Batches, out)
	}
	return p, nil
}

func makeItem(cat *catalog.Catalog, g *graph.Graph, rc registry.Client, n graph.Node, overrides map[string]string, bumpMinor bool, rebuilt map[graph.Node]bool) (Item, error) {
	svc := cat.Families[n.Family].Services[n.Service]
	in, err := hash.Input(cat, g, n, overrides)
	if err != nil {
		return Item{}, err
	}
	args, err := cat.BuildArgs(n.Family, n.Service, hash.Declared(g.File(n).ArgDecls), overrides)
	if err != nil {
		return Item{}, err
	}
	local, upstreamKeys := g.Parents(n)
	up := map[string]string{}
	for _, k := range upstreamKeys {
		u := cat.Upstream[k]
		up[k+"_IMAGE"] = stripTag(u.Ref) + "@" + u.Digest
	}

	repo := cat.Registry + "/" + n.Family
	all, err := rc.ListTags(repo)
	if err != nil {
		return Item{}, err
	}
	var existing []string
	for _, t := range all {
		if strings.HasPrefix(t, n.Service+"-") {
			existing = append(existing, t)
		}
	}
	sort.Strings(existing)

	it := Item{Family: n.Family, Service: n.Service, Class: svc.Class, InputHash: in, BuildArgs: args, Upstream: up}
	// 上層重建會換新 tag，子層即使 label 吻合也必須跟著重建。
	parentRebuilt := anyRebuilt(local, rebuilt)
	for _, t := range existing {
		if parentRebuilt {
			break
		}
		got, err := rc.Label(repo+":"+t, HashLabel)
		if err != nil {
			return Item{}, err
		}
		if got == in {
			it.Tag = t
			it.Reason = "輸入未變"
			return it, nil
		}
	}

	it.Rebuild = true
	switch {
	case len(existing) == 0:
		it.Reason = "無既有映像"
	case parentRebuilt:
		it.Reason = "上層重建"
	default:
		it.Reason = "輸入改變"
	}
	if svc.Class != "B" {
		ver := svc.Version
		it.Tag, err = tag.Next(svc.Class, n.Service, ver, existing, bumpMinor)
		if err != nil {
			return Item{}, err
		}
	}
	return it, nil
}

func anyRebuilt(parents []graph.Node, rebuilt map[graph.Node]bool) bool {
	for _, p := range parents {
		if rebuilt[p] {
			return true
		}
	}
	return false
}

// stripTag 去掉 ref 結尾的 :tag（不誤傷 host:port）。
func stripTag(ref string) string {
	i := strings.LastIndex(ref, ":")
	if i > strings.LastIndex(ref, "/") {
		return ref[:i]
	}
	return ref
}
