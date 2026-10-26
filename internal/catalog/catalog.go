// Package catalog 載入並驗證 catalog.yaml，並依 family 組出 Dockerfile 的 build-arg 值表。
package catalog

import (
	"bytes"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

// Catalog 對應 catalog.yaml 的頂層。
type Catalog struct {
	Registry     string              `yaml:"registry"`
	ProvisionRef string              `yaml:"provision_ref"`
	Upstream     map[string]Upstream `yaml:"upstream"`
	Families     map[string]Family   `yaml:"families"`
}

// Upstream 是同步進自家 registry 的上游映像。Digest 以 sha256: 開頭。
type Upstream struct {
	Ref    string `yaml:"ref"`
	Digest string `yaml:"digest"`
}

// Family 的 Aliases 把 Dockerfile 的 ARG 名對應到 catalog 鍵。
type Family struct {
	Values   map[string]string  `yaml:"values"`
	Aliases  map[string]string  `yaml:"aliases"`
	Services map[string]Service `yaml:"services"`
}

// Service 的 Class 是 "A"、"B" 或 "C"。A 類寫 Version，B 類寫 VersionFrom，C 類兩者都不寫。
type Service struct {
	Class       string       `yaml:"class"`
	Version     string       `yaml:"version"`
	VersionFrom *VersionFrom `yaml:"version_from"`
	Tests       string       `yaml:"tests"`
}

// VersionFrom 的 Package 與 Command 二擇一。
type VersionFrom struct {
	Package string `yaml:"package"`
	Command string `yaml:"command"`
}

// Load 讀 path 並驗證。錯誤訊息帶 YAML 欄位路徑，例如 families.alpine.services.sshd.class。
func Load(path string) (*Catalog, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("讀不到 %s：%w", path, err)
	}
	var root yaml.Node
	if err := yaml.Unmarshal(raw, &root); err != nil {
		return nil, fmt.Errorf("%s：%w", path, err)
	}
	dec := yaml.NewDecoder(bytes.NewReader(raw))
	dec.KnownFields(true)
	var c Catalog
	if err := dec.Decode(&c); err != nil {
		return nil, fmt.Errorf("%s：%s", path, withPaths(err, &root))
	}
	if err := c.validate(); err != nil {
		return nil, fmt.Errorf("%s：%w", path, err)
	}
	return &c, nil
}

var (
	lineRe   = regexp.MustCompile(`line (\d+): (?:field (\S+) not found)?`)
	digestRe = regexp.MustCompile(`^sha256:[0-9a-f]{64}$`)
)

// withPaths 把 yaml.v3 錯誤訊息裡的行號換成欄位路徑，因為 yaml.v3 只報行號。
func withPaths(err error, root *yaml.Node) string {
	return lineRe.ReplaceAllStringFunc(err.Error(), func(m string) string {
		sub := lineRe.FindStringSubmatch(m)
		n, _ := strconv.Atoi(sub[1])
		if p := pathAtLine(root, n, sub[2]); p != "" {
			return "欄位 " + p + "：" + m
		}
		return m
	})
}

// pathAtLine 找出位於第 line 行的 key 的路徑；name 非空時只取同名的 key，否則取最深的。
func pathAtLine(root *yaml.Node, line int, name string) string {
	best, bestDepth := "", -1
	var walk func(n *yaml.Node, prefix []string)
	walk = func(n *yaml.Node, prefix []string) {
		switch n.Kind {
		case yaml.DocumentNode:
			for _, ch := range n.Content {
				walk(ch, prefix)
			}
		case yaml.MappingNode:
			for i := 0; i+1 < len(n.Content); i += 2 {
				k, v := n.Content[i], n.Content[i+1]
				p := append(append([]string{}, prefix...), k.Value)
				if k.Line == line && (name == "" || k.Value == name) && len(p) > bestDepth {
					best, bestDepth = strings.Join(p, "."), len(p)
				}
				walk(v, p)
			}
		}
	}
	walk(root, nil)
	return best
}

func sortedKeys[V any](m map[string]V) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

func (c *Catalog) validate() error {
	var errs []string
	add := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }
	for _, name := range sortedKeys(c.Upstream) {
		u := c.Upstream[name]
		if u.Ref == "" {
			add("upstream.%s.ref 不得為空", name)
		}
		if !strings.HasPrefix(u.Digest, "sha256:") {
			add("upstream.%s.digest 要以 sha256: 開頭，現為 %q", name, u.Digest)
		} else if !digestRe.MatchString(u.Digest) {
			add("upstream.%s.digest 格式不對，要 sha256: 加 64 位小寫十六進位", name)
		}
	}
	for _, fam := range sortedKeys(c.Families) {
		for _, svc := range sortedKeys(c.Families[fam].Services) {
			s := c.Families[fam].Services[svc]
			p := fmt.Sprintf("families.%s.services.%s", fam, svc)
			switch s.Class {
			case "A":
				if s.Version == "" {
					add("%s.version：class A 必填", p)
				}
				if s.VersionFrom != nil {
					add("%s.version_from：class A 不得有", p)
				}
			case "B":
				vf := s.VersionFrom
				switch {
				case vf == nil:
					add("%s.version_from：class B 必填", p)
				case (vf.Package == "") == (vf.Command == ""):
					add("%s.version_from：package 與 command 要二擇一", p)
				}
				if s.Version != "" {
					add("%s.version：class B 不得有", p)
				}
			case "C":
				if s.Version != "" || s.VersionFrom != nil {
					add("%s：class C 不得有 version 或 version_from", p)
				}
			default:
				add("%s.class：要是 A、B 或 C，現為 %q", p, s.Class)
			}
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "；"))
	}
	return nil
}

// BuildArgs 組出 declared 裡每個光桿 ARG 的值。
// 來源依序是 PROVISION_REF、family Values、overrides，後者蓋前者。
// Aliases 把 ARG 名換成 catalog 鍵再查。*_IMAGE 不由本函式供給。
func (c *Catalog) BuildArgs(family, service string, declared []string, overrides map[string]string) (map[string]string, error) {
	fam, ok := c.Families[family]
	if !ok {
		return nil, fmt.Errorf("catalog 沒有 family %q", family)
	}
	if _, ok := fam.Services[service]; !ok {
		return nil, fmt.Errorf("catalog 沒有 service %s/%s", family, service)
	}
	out := map[string]string{}
	var missing []string
	for _, arg := range declared {
		key := arg
		if a, ok := fam.Aliases[arg]; ok {
			key = a
		}
		switch {
		case overrides != nil && hasKey(overrides, key):
			out[arg] = overrides[key]
		case overrides != nil && hasKey(overrides, arg):
			out[arg] = overrides[arg]
		case hasKey(fam.Values, key):
			out[arg] = fam.Values[key]
		case key == "PROVISION_REF" && c.ProvisionRef != "":
			out[arg] = c.ProvisionRef
		default:
			missing = append(missing, arg)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("%s/%s 的光桿 ARG 查不到值：%s", family, service, strings.Join(missing, "、"))
	}
	return out, nil
}

func hasKey(m map[string]string, k string) bool { _, ok := m[k]; return ok }
