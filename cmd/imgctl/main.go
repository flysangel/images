// imgctl 是 images repo 的建置工具；原型階段只處理 alpine family。
package main

import (
	"fmt"
	"os"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/lint"
)

// commands 列出子命令；值是實作，nil 表示尚未實作。
var commands = map[string]func(args []string) int{
	"lint":    runLint,
	"plan":    nil,
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
