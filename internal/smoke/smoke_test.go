package smoke

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const specYAML = `
defaults: { privileged: true, ssh: { user: bigred, password: bigred }, wait_port: 22 }
services:
  base:     { ssh: null, wait_port: null, commands: [sudo, bash], timezone: Asia/Taipei }
  sshd:     {}
  runner:   { ssh: null, wait_port: null, privileged: false, commands: [git] }
  k8sadm:   { commands: [kind], files: [{ path: /home/bigred/.kube/config.tmp, mode: "600", owner: bigred }] }
  esc:      { script: infra/alpine/esc.sh }
`

func load(t *testing.T, svc string) Spec {
	p := filepath.Join(t.TempDir(), "tests.yaml")
	if err := os.WriteFile(p, []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	s, err := LoadSpec(p, svc)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestLoadSpec(t *testing.T) {
	sshd := load(t, "sshd")
	if !sshd.Privileged || sshd.SSH == nil || sshd.SSH.User != "bigred" || sshd.WaitPort == nil || *sshd.WaitPort != 22 {
		t.Errorf("sshd 應繼承 defaults：%+v", sshd)
	}
	base := load(t, "base")
	if base.SSH != nil || base.WaitPort != nil || !base.Privileged {
		t.Errorf("base 的 null 應蓋掉 defaults，privileged 仍繼承：%+v", base)
	}
	runner := load(t, "runner")
	if runner.Privileged || runner.SSH != nil {
		t.Errorf("runner：%+v", runner)
	}
	if _, err := LoadSpec(filepath.Join(t.TempDir(), "none.yaml"), "x"); err == nil {
		t.Error("檔案不存在應回錯")
	}
	p := filepath.Join(t.TempDir(), "t.yaml")
	os.WriteFile(p, []byte(specYAML), 0o644)
	if _, err := LoadSpec(p, "nosuch"); err == nil {
		t.Error("沒有該 service 應回錯")
	}
}

func join(steps [][]string) string {
	var b []string
	for _, s := range steps {
		b = append(b, strings.Join(s, " "))
	}
	return strings.Join(b, "\n")
}

func TestSteps(t *testing.T) {
	out := join(Steps(load(t, "k8sadm"), "10.0.0.5", "ctr1"))
	for _, want := range []string{
		"sshpass -p bigred ssh",
		"bigred@10.0.0.5",
		"docker exec ctr1 sh -c command -v kind",
		"stat -c '%a %U' /home/bigred/.kube/config.tmp",
		"600 bigred",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("缺 %q\n%s", want, out)
		}
	}
	// ssh 只驗登入：其餘檢查一律走 docker exec（非互動 ssh 的 PATH 可能缺 /usr/local/bin）。
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, "sshpass") && !strings.HasSuffix(line, "echo ssh test ok") {
			t.Errorf("ssh 只該用來驗登入：%s", line)
		}
	}
}

func TestStepsExecMode(t *testing.T) {
	out := join(Steps(load(t, "base"), "", "ctr1"))
	for _, want := range []string{"docker exec ctr1 sh -c", "command -v sudo", "Asia/Taipei"} {
		if !strings.Contains(out, want) {
			t.Errorf("缺 %q\n%s", want, out)
		}
	}
	if strings.Contains(out, "sshpass") {
		t.Errorf("exec 模式不該用 ssh：%s", out)
	}
}

func TestStepsScript(t *testing.T) {
	steps := Steps(load(t, "esc"), "10.0.0.5", "ctr1")
	if len(steps) != 1 || !slices.Equal(steps[0], []string{"bash", "infra/alpine/esc.sh", "10.0.0.5"}) {
		t.Errorf("%v", steps)
	}
}

func TestRunArgs(t *testing.T) {
	got := strings.Join(RunArgs(load(t, "sshd"), "img", "c1"), " ")
	if got != "docker run -d --privileged --name c1 img" {
		t.Errorf("sshd：%s", got)
	}
	got = strings.Join(RunArgs(load(t, "runner"), "img", "c1"), " ")
	if got != "docker run -d --name c1 --entrypoint sleep img 3600" {
		t.Errorf("runner：%s", got)
	}
}

// 實際的 tests.yaml 要能載入，且每個 catalog service 都有規格。
func TestRealSpec(t *testing.T) {
	for _, svc := range []string{"base", "sshd", "podman", "qemu", "s3cli", "k8stools", "k8sadm", "runner"} {
		if _, err := LoadSpec("../../infra/alpine/tests.yaml", svc); err != nil {
			t.Errorf("%s：%v", svc, err)
		}
	}
}
