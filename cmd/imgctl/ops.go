package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/flysangel/images/internal/build"
	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/plan"
	"github.com/flysangel/images/internal/promote"
	"github.com/flysangel/images/internal/registry"
	"github.com/flysangel/images/internal/smoke"
	"github.com/flysangel/images/internal/tag"
)

// 這幾個子命令跑在 GitHub Actions 上（有 docker、buildx）；邏輯在 internal/ 的純函式，
// 這裡只負責讀旗標、呼叫外部指令、印訊息。

func fail(format string, a ...any) int {
	fmt.Fprintf(os.Stderr, "Error: "+format+"\n", a...)
	return 1
}

// parseFlags 解析旗標；失敗回傳 2（用法錯誤）。
func parseFlags(name string, args []string, setup func(fs *flag.FlagSet)) (ok bool) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	setup(fs)
	return fs.Parse(args) == nil
}

// splitService 把 `alpine:sshd` 拆成 family 與 service。
func splitService(s string) (string, string, error) {
	f, v, ok := strings.Cut(s, ":")
	if !ok || f == "" || v == "" {
		return "", "", fmt.Errorf("--service 要寫成 <family>:<service>，收到 %q", s)
	}
	return f, v, nil
}

func loadPlan(path string) (*plan.Plan, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var p plan.Plan
	if err := json.Unmarshal(b, &p); err != nil {
		return nil, fmt.Errorf("%s：%w", path, err)
	}
	return &p, nil
}

func findItem(p *plan.Plan, family, service string) (plan.Item, bool) {
	for _, b := range p.Batches {
		for _, it := range b {
			if it.Family == family && it.Service == service {
				return it, true
			}
		}
	}
	return plan.Item{}, false
}

// runCmd 執行外部指令，輸出接到 stderr（stdout 留給純資料）。
func runCmd(argv []string) error {
	c := exec.Command(argv[0], argv[1:]...)
	c.Stdout, c.Stderr = os.Stderr, os.Stderr
	return c.Run()
}

// runBuild 用法：imgctl build --plan plan.json --service alpine:sshd --parents <dir> --push <repo> --sha <commit> [--out <dir>]
func runBuild(args []string) int {
	var planPath, service, parentsDir, push, sha, out string
	if !parseFlags("build", args, func(fs *flag.FlagSet) {
		fs.StringVar(&planPath, "plan", "", "plan.json")
		fs.StringVar(&service, "service", "", "<family>:<service>")
		fs.StringVar(&parentsDir, "parents", ".", "放上層 .ref 檔的目錄")
		fs.StringVar(&push, "push", "", "staging repo，例如 ghcr.io/flysangel/images-staging")
		fs.StringVar(&sha, "sha", "", "commit sha，用於臨時 tag")
		fs.StringVar(&out, "out", ".", "寫 .ref 檔的目錄")
	}) {
		return 2
	}
	if planPath == "" || service == "" || push == "" || sha == "" {
		return fail("build 需要 --plan、--service、--push、--sha")
	}
	fam, svc, err := splitService(service)
	if err != nil {
		return fail("%v", err)
	}
	p, err := loadPlan(planPath)
	if err != nil {
		return fail("%v", err)
	}
	item, ok := findItem(p, fam, svc)
	if !ok {
		return fail("plan 裡沒有 %s", service)
	}
	if !item.Rebuild {
		fmt.Fprintf(os.Stderr, "Info: %s 輸入未變，不重建\n", service)
		return 0
	}
	cat, err := catalog.Load("catalog.yaml")
	if err != nil {
		return fail("%v", err)
	}
	rc := registry.New()
	parents, err := build.ResolveParents(item, p, parentsDir, cat.Registry, rc)
	if err != nil {
		return fail("%v", err)
	}
	argv, err := build.Command(item, parents, push, sha)
	if err != nil {
		return fail("%v", err)
	}
	fmt.Fprintf(os.Stderr, "Info: %s\n", strings.Join(argv, " "))
	if err := runCmd(argv); err != nil {
		return fail("buildx 失敗：%v", err)
	}
	ref := push + "/" + fam + ":" + build.StagingTag(item, sha)
	digest, err := rc.Digest(ref)
	if err != nil {
		return fail("查 %s 的 digest 失敗：%v", ref, err)
	}
	refFile := filepath.Join(out, fam+"_"+svc+".ref")
	if err := os.WriteFile(refFile, []byte(ref+"@"+digest+"\n"), 0o644); err != nil {
		return fail("%v", err)
	}
	fmt.Printf("Success: %s 已推到 %s@%s\n", service, ref, digest)
	return 0
}

// runTest 用法：imgctl test --service alpine:sshd --image <ref> [--spec infra/alpine/tests.yaml]
func runTest(args []string) int {
	var service, image, specPath string
	if !parseFlags("test", args, func(fs *flag.FlagSet) {
		fs.StringVar(&service, "service", "", "<family>:<service>")
		fs.StringVar(&image, "image", "", "要測的映像 ref")
		fs.StringVar(&specPath, "spec", "", "tests.yaml 路徑（預設 infra/<family>/tests.yaml）")
	}) {
		return 2
	}
	if service == "" || image == "" {
		return fail("test 需要 --service、--image")
	}
	fam, svc, err := splitService(service)
	if err != nil {
		return fail("%v", err)
	}
	if specPath == "" {
		specPath = "infra/" + fam + "/tests.yaml"
	}
	spec, err := smoke.LoadSpec(specPath, svc)
	if err != nil {
		return fail("%v", err)
	}
	name := fmt.Sprintf("imgctl-test-%d", os.Getpid())
	if err := runCmd(smoke.RunArgs(spec, image, name)); err != nil {
		return fail("起容器失敗：%v", err)
	}
	defer exec.Command("docker", "rm", "-f", name).Run()

	ip := ""
	if spec.SSH != nil {
		out, err := exec.Command("docker", "inspect", "-f", "{{.NetworkSettings.IPAddress}}", name).Output()
		if err != nil {
			return fail("docker inspect 失敗：%v", err)
		}
		ip = strings.TrimSpace(string(out))
		if spec.WaitPort != nil {
			if err := waitPort(ip, *spec.WaitPort, 60*time.Second); err != nil {
				return fail("%v", err)
			}
		}
	}
	failed := 0
	for _, step := range smoke.Steps(spec, ip, name) {
		label := step[len(step)-1]
		if spec.Script != "" {
			label = spec.Script
		}
		c := exec.Command(step[0], step[1:]...)
		c.Stdout, c.Stderr = os.Stderr, os.Stderr
		if err := c.Run(); err != nil {
			fmt.Printf("[FAIL] %s\n", label)
			failed++
			continue
		}
		fmt.Printf("[OK] %s\n", label)
	}
	if failed > 0 {
		return fail("%s 有 %d 項失敗", service, failed)
	}
	fmt.Printf("Success: %s 煙霧測試通過\n", service)
	return 0
}

func waitPort(ip string, port int, limit time.Duration) error {
	addr := net.JoinHostPort(ip, strconv.Itoa(port))
	deadline := time.Now().Add(limit)
	for time.Now().Before(deadline) {
		if c, err := net.DialTimeout("tcp", addr, 2*time.Second); err == nil {
			c.Close()
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("等 %s 逾時（%s）", addr, limit)
}

// runVersion 用法：imgctl version --plan plan.json --service alpine:sshd --image <ref> [--existing-from quay]
// stdout 只印 tag。
func runVersion(args []string) int {
	var planPath, service, image, existingFrom string
	if !parseFlags("version", args, func(fs *flag.FlagSet) {
		fs.StringVar(&planPath, "plan", "", "plan.json")
		fs.StringVar(&service, "service", "", "<family>:<service>")
		fs.StringVar(&image, "image", "", "乙類探測版本用的映像 ref")
		fs.StringVar(&existingFrom, "existing-from", "quay", "既有 tag 的來源（目前只有 quay）")
	}) {
		return 2
	}
	if planPath == "" || service == "" {
		return fail("version 需要 --plan、--service")
	}
	if existingFrom != "quay" {
		return fail("--existing-from 目前只支援 quay")
	}
	fam, svc, err := splitService(service)
	if err != nil {
		return fail("%v", err)
	}
	p, err := loadPlan(planPath)
	if err != nil {
		return fail("%v", err)
	}
	item, ok := findItem(p, fam, svc)
	if !ok {
		return fail("plan 裡沒有 %s", service)
	}
	if item.Class != "B" || !item.Rebuild {
		if item.Tag == "" {
			return fail("plan 裡 %s 沒有 tag", service)
		}
		fmt.Println(item.Tag)
		return 0
	}
	if image == "" {
		return fail("乙類 service 需要 --image")
	}
	cat, err := catalog.Load("catalog.yaml")
	if err != nil {
		return fail("%v", err)
	}
	kind, argv, err := build.ProbeCommand(fam, cat.Families[fam].Services[svc].VersionFrom, image)
	if err != nil {
		return fail("%v", err)
	}
	c := exec.Command(argv[0], argv[1:]...)
	c.Stderr = os.Stderr
	raw, err := c.Output()
	if err != nil {
		return fail("探測版本失敗：%v", err)
	}
	ver, err := tag.ParseVersionOutput(kind, string(raw))
	if err != nil {
		return fail("%v", err)
	}
	existing, err := registry.New().ListTags(cat.Registry + "/" + fam)
	if err != nil {
		return fail("%v", err)
	}
	t, err := tag.Next("B", svc, tag.Sanitize(ver), existing, false)
	if err != nil {
		return fail("%v", err)
	}
	fmt.Println(t)
	return 0
}

// runPromote 用法：imgctl promote --from <ref@digest> --to quay.io/flysangel/alpine:<tag>
func runPromote(args []string) int {
	var from, to string
	if !parseFlags("promote", args, func(fs *flag.FlagSet) {
		fs.StringVar(&from, "from", "", "來源 ref@digest")
		fs.StringVar(&to, "to", "", "目的 ref")
	}) {
		return 2
	}
	if from == "" || to == "" {
		return fail("promote 需要 --from、--to")
	}
	if err := promote.Promote(registry.New(), from, to); err != nil {
		return fail("%v", err)
	}
	fmt.Printf("Success: 已推進 %s\n", to)
	return 0
}
