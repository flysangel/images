// Package dockerfile 用 BuildKit parser 解析 Dockerfile，取出 lint 要用的 ARG、ENV 與 stage 資訊。
package dockerfile

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/moby/buildkit/frontend/dockerfile/parser"
)

// File 是解析後的 Dockerfile。
type File struct {
	Path       string
	GlobalArgs []string // 第一個 FROM 之前的 ARG 名
	Stages     []Stage
	ArgDecls   []ArgDecl // 全檔每個 ARG（含全域），依出現順序
	Envs       []EnvDecl // 全檔每個 ENV 鍵
	// IgnoreBeforeArg 是「緊接在 # hadolint ignore= 註解後的非空行是 ARG」的那些 ARG 行號。
	IgnoreBeforeArg []int
}

// Stage 是一個 FROM 起算的 build stage。
type Stage struct {
	FromArg  string // FROM ${X} 的 X；FROM 不是這個寫法時為空
	From     string // FROM 後的映像參照原文
	Line     int    // FROM 的行號
	Args     []string
	UsedVars []string // stage 內（不含 ARG 行與 FROM 行）以 $X 或 ${X} 引用的變數
}

// ArgDecl 是一個 ARG 宣告。HasDefault 為 false 的就是光桿 ARG（契約值）。
type ArgDecl struct {
	Name       string
	HasDefault bool
	Line       int
	Stage      int // 所屬 stage 的索引；全域 ARG 為 -1
}

// EnvDecl 是一個 ENV 鍵。
type EnvDecl struct {
	Name string
	Line int
}

var (
	fromArgRe = regexp.MustCompile(`^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$`)
	varRe     = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)[^}]*\}|\$([A-Za-z_][A-Za-z0-9_]*)`)
	ignoreRe  = regexp.MustCompile(`^\s*#\s*hadolint\s+ignore=`)
)

// Parse 讀 path 並解析。
func Parse(path string) (*File, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("讀不到 %s：%w", path, err)
	}
	res, err := parser.Parse(strings.NewReader(string(raw)))
	if err != nil {
		return nil, fmt.Errorf("%s：解析失敗：%w", path, err)
	}
	f := &File{Path: path}
	cur := -1
	for _, n := range res.AST.Children {
		switch strings.ToLower(n.Value) {
		case "from":
			s := Stage{Line: n.StartLine}
			if n.Next != nil {
				s.From = n.Next.Value
				if m := fromArgRe.FindStringSubmatch(s.From); m != nil {
					s.FromArg = m[1]
				}
			}
			f.Stages = append(f.Stages, s)
			cur = len(f.Stages) - 1
		case "arg":
			for a := n.Next; a != nil; a = a.Next {
				name, _, hasDef := strings.Cut(a.Value, "=")
				f.ArgDecls = append(f.ArgDecls, ArgDecl{Name: name, HasDefault: hasDef, Line: n.StartLine, Stage: cur})
				if cur < 0 {
					f.GlobalArgs = append(f.GlobalArgs, name)
				} else {
					f.Stages[cur].Args = append(f.Stages[cur].Args, name)
				}
			}
		default:
			if strings.ToLower(n.Value) == "env" {
				// ENV 的 Next 鏈依序是「鍵、值、=」；舊寫法 ENV K V 只有「鍵、值」。
				for a := n.Next; a != nil; {
					f.Envs = append(f.Envs, EnvDecl{Name: a.Value, Line: n.StartLine})
					if a.Next != nil && a.Next.Next != nil && a.Next.Next.Value == "=" {
						a = a.Next.Next.Next
					} else if a.Next != nil {
						a = a.Next.Next
					} else {
						a = nil
					}
				}
			}
			if cur >= 0 {
				f.Stages[cur].UsedVars = addVars(f.Stages[cur].UsedVars, n.Original)
			}
		}
	}
	f.IgnoreBeforeArg = ignoreBeforeArg(string(raw))
	return f, nil
}

// addVars 把 text 裡引用的變數名加進 dst，去重並保持出現順序。
func addVars(dst []string, text string) []string {
	for _, m := range varRe.FindAllStringSubmatch(text, -1) {
		name := m[1]
		if name == "" {
			name = m[2]
		}
		dup := false
		for _, d := range dst {
			if d == name {
				dup = true
				break
			}
		}
		if !dup {
			dst = append(dst, name)
		}
	}
	return dst
}

// ignoreBeforeArg 掃原文：# hadolint ignore= 之後的下一個非空行若是 ARG，記下該行行號。
// 這裡不用 AST，因為 parser 會丟掉註解。
func ignoreBeforeArg(src string) []int {
	var out []int
	pending := false
	for i, line := range strings.Split(src, "\n") {
		t := strings.TrimSpace(line)
		switch {
		case t == "":
			continue
		case pending:
			if fields := strings.Fields(t); len(fields) > 0 && strings.EqualFold(fields[0], "ARG") {
				out = append(out, i+1)
			}
			pending = ignoreRe.MatchString(line)
		default:
			pending = ignoreRe.MatchString(line)
		}
	}
	return out
}

// ImageArgName 回傳 family 的 service 對應的 FROM 用 ARG 名，例如 alpine、sshd 得 ALPINE_SSHD_IMAGE。
func ImageArgName(family, service string) string {
	return strings.ToUpper(strings.ReplaceAll(family+"_"+service, "-", "_")) + "_IMAGE"
}
