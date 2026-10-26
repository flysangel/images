// Package lint 檢查已遷移到 imgctl 的 family（有 .imgctl 標記）的 Dockerfile 與 catalog 是否一致。
package lint

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/dockerfile"
)

// Finding 是一筆違規。Line 為 0 表示整檔層級。
type Finding struct {
	File string
	Line int
	Msg  string
}

func (f Finding) String() string { return fmt.Sprintf("%s:%d: %s", f.File, f.Line, f.Msg) }

var imageArgRe = regexp.MustCompile(`^[A-Z0-9_]+_IMAGE$`)

// Run 對 catalog 內每個有 infra/<family>/.imgctl 的 family 跑六條規則。
func Run(cat *catalog.Catalog, repoRoot string) []Finding {
	// 允許當 FROM 的映像 ARG 名：任一 family 的 service，加上 upstream 鍵。
	allowed := map[string]bool{}
	for fam, f := range cat.Families {
		for svc := range f.Services {
			allowed[dockerfile.ImageArgName(fam, svc)] = true
		}
	}
	for k := range cat.Upstream {
		allowed[strings.ToUpper(k)+"_IMAGE"] = true
	}
	var out []Finding
	fams := make([]string, 0, len(cat.Families))
	for fam := range cat.Families {
		fams = append(fams, fam)
	}
	sort.Strings(fams)
	for _, fam := range fams {
		dir := filepath.Join(repoRoot, "infra", fam)
		if _, err := os.Stat(filepath.Join(dir, ".imgctl")); err != nil {
			continue
		}
		out = append(out, lintFamily(cat, fam, dir, repoRoot, allowed)...)
	}
	// 反向檢查：有 .imgctl 標記、catalog 卻沒有的 family，舊 lint 也會略過，不報就沒人看。
	markers, _ := filepath.Glob(filepath.Join(repoRoot, "infra", "*", ".imgctl"))
	sort.Strings(markers)
	for _, m := range markers {
		fam := filepath.Base(filepath.Dir(m))
		if _, ok := cat.Families[fam]; !ok {
			r, _ := filepath.Rel(repoRoot, m)
			out = append(out, Finding{r, 0, fmt.Sprintf("infra/%s 有 .imgctl 標記，但 catalog 沒有 family %s", fam, fam)})
		}
	}
	return out
}

func lintFamily(cat *catalog.Catalog, fam, dir, repoRoot string, allowed map[string]bool) []Finding {
	var out []Finding
	rel := func(p string) string { r, _ := filepath.Rel(repoRoot, p); return r }
	files, _ := filepath.Glob(filepath.Join(dir, "*.Dockerfile"))
	sort.Strings(files)
	have := map[string]bool{}
	for _, p := range files {
		svc := strings.TrimSuffix(filepath.Base(p), ".Dockerfile")
		have[svc] = true
		if _, ok := cat.Families[fam].Services[svc]; !ok {
			out = append(out, Finding{rel(p), 0, fmt.Sprintf("catalog 的 families.%s.services 沒有 %s", fam, svc)})
			continue
		}
		out = append(out, lintFile(cat, fam, svc, p, rel(p), allowed)...)
	}
	svcs := make([]string, 0)
	for svc := range cat.Families[fam].Services {
		svcs = append(svcs, svc)
	}
	sort.Strings(svcs)
	for _, svc := range svcs {
		if !have[svc] {
			out = append(out, Finding{rel(filepath.Join(dir, svc+".Dockerfile")), 0, fmt.Sprintf("catalog 有 service %s，但沒有對應的 Dockerfile", svc)})
		}
	}
	return out
}

func lintFile(cat *catalog.Catalog, fam, svc, path, name string, allowed map[string]bool) []Finding {
	f, err := dockerfile.Parse(path)
	if err != nil {
		return []Finding{{name, 0, err.Error()}}
	}
	var out []Finding
	add := func(line int, format string, a ...any) {
		out = append(out, Finding{name, line, fmt.Sprintf(format, a...)})
	}

	// 規則 1：FROM 只能是 ${X_IMAGE}，X_IMAGE 要是同 repo 的 service 或 upstream。
	for _, s := range f.Stages {
		switch {
		case s.FromArg == "" || !imageArgRe.MatchString(s.FromArg):
			add(s.Line, "FROM 只能寫 ${X_IMAGE}，現為 %q", s.From)
		case !allowed[s.FromArg]:
			add(s.Line, "FROM 用的 %s 不是任何 service 或 upstream 的映像 ARG", s.FromArg)
		}
	}

	// 規則 2：光桿 ARG（_IMAGE 除外）要供得出值。逐個查，才能指出行號。
	contract := map[string]bool{}
	for _, a := range f.ArgDecls {
		if a.HasDefault || strings.HasSuffix(a.Name, "_IMAGE") {
			continue
		}
		contract[a.Name] = true
		if _, err := cat.BuildArgs(fam, svc, []string{a.Name}, nil); err != nil {
			add(a.Line, "光桿 ARG %s 供不出值：%v", a.Name, err)
		}
	}
	// catalog 的 values 鍵與別名也算契約鍵，stage 用到卻沒宣告就是漏宣告。
	famCfg := cat.Families[fam]
	for k := range famCfg.Values {
		contract[k] = true
	}
	for k := range famCfg.Aliases {
		contract[k] = true
	}

	// 規則 3：stage 內用到的契約鍵，該 stage 要自己宣告（ARG 不跨 stage）。
	for _, s := range f.Stages {
		declared := map[string]bool{}
		for _, a := range s.Args {
			declared[a] = true
		}
		for _, v := range s.UsedVars {
			if contract[v] && !declared[v] {
				add(s.Line, "stage 用到契約鍵 %s，但該 stage 沒有宣告 ARG %s（ARG 不跨 stage，會靜默展開成空字串）", v, v)
			}
		}
	}

	// 規則 4：同名的光桿 ARG 與 ENV 不得並存（父映像或本檔的 ENV 會蓋掉 ARG）。
	bare := map[string]bool{}
	for _, a := range f.ArgDecls {
		if !a.HasDefault {
			bare[a.Name] = true
		}
	}
	for _, e := range f.Envs {
		if bare[e.Name] {
			add(e.Line, "光桿 ARG 與 ENV 同名：%s", e.Name)
		}
	}

	// 規則 5：hadolint ignore 註解的下一個非空行不得是 ARG。
	for _, ln := range f.IgnoreBeforeArg {
		add(ln, "hadolint ignore 註解後面緊接 ARG，抑制目標會變成 ARG；把 ARG 移到註解之上")
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Line < out[j].Line })
	return out
}
