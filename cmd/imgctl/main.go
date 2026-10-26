// imgctl 是 images repo 的建置工具；原型階段只處理 alpine family。
package main

import (
	"fmt"
	"os"
)

// commands 列出子命令；值是實作，nil 表示尚未實作。
var commands = map[string]func(args []string) int{
	"lint":    nil,
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
