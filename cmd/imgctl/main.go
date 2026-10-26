// imgctl 是 images repo 的建置工具；原型階段只處理 alpine family。
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/graph"
	"github.com/flysangel/images/internal/lint"
	"github.com/flysangel/images/internal/plan"
	"github.com/flysangel/images/internal/registry"
)

// commands 列出子命令；值是實作，nil 表示尚未實作。
var commands = map[string]func(args []string) int{
	"lint":    runLint,
	"plan":    runPlan,
	"build":   nil,
	"test":    nil,
	"version": nil,
	"promote": nil,
}

func main() { os.Exit(run(os.Args[1:])) }

func run(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Error: 用法：imgctl <lint|plan|build|test|version|promote>")
		return 2
	}
	fn, ok := commands[args[0]]
	if !ok {
		fmt.Fprintf(os.Stderr, "Error: 不認得的子命令 %s\n", args[0])
		return 2
	}
	if fn == nil {
		fmt.Fprintln(os.Stderr, "Error: not implemented")
		return 1
	}
	return fn(args[1:])
}

// runLint 從目前目錄（repo 根）載入 catalog.yaml 並檢查已遷移 family 的 Dockerfile。
func runLint(args []string) int {
	cat, err := catalog.Load("catalog.yaml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	findings := lint.Run(cat, ".")
	for _, f := range findings {
		fmt.Fprintf(os.Stderr, "Error: %s\n", f)
	}
	if len(findings) > 0 {
		return 1
	}
	fmt.Println("Success: imgctl lint 通過")
	return 0
}

// runPlan 比對 registry 現況並印出每個 service 要不要重建。
// 用法：imgctl plan [--json] [--bump-minor] [KEY=VAL ...]
func runPlan(args []string) int {
	asJSON, bumpMinor := false, false
	overrides := map[string]string{}
	for _, a := range args {
		switch {
		case a == "--json":
			asJSON = true
		case a == "--bump-minor":
			bumpMinor = true
		case strings.Contains(a, "=") && !strings.HasPrefix(a, "-"):
			k, v, _ := strings.Cut(a, "=")
			overrides[k] = v
		default:
			fmt.Fprintf(os.Stderr, "Error: 不認得的參數 %s\n", a)
			return 2
		}
	}
	cat, err := catalog.Load("catalog.yaml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	g, err := graph.Build(cat, ".")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	p, err := plan.Make(cat, g, registry.New(), overrides, bumpMinor)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	if asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(p); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			return 1
		}
		return 0
	}
	fmt.Printf("%-16s %-8s %-10s %s\n", "SERVICE", "重建", "原因", "TAG")
	for _, b := range p.Batches {
		for _, it := range b {
			t := it.Tag
			if t == "" {
				t = "建完才定"
			}
			fmt.Printf("%-16s %-8v %-10s %s\n", it.Family+"/"+it.Service, it.Rebuild, it.Reason, t)
		}
	}
	return 0
}
