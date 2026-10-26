// Package smoke 讀 tests.yaml，並把煙霧測試展開成要執行的指令。
// 這裡只組指令，不執行；執行由 cmd/imgctl 負責，所以不需要 docker 就能測。
package smoke

import (
	"bytes"
	"fmt"
	"os"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

// SSH 是登入容器用的帳密。
type SSH struct {
	User     string `yaml:"user"`
	Password string `yaml:"password"`
}

// FileCheck 驗檔案的權限與擁有者。
type FileCheck struct {
	Path  string `yaml:"path"`
	Mode  string `yaml:"mode"`
	Owner string `yaml:"owner"`
}

// Spec 是合併 defaults 之後，一個 service 的測試規格。
// SSH 為 nil 表示不做 ssh 登入檢查；SSH 與 WaitPort 都是 nil 表示容器沒有長駐服務，改用 docker exec 驗。
type Spec struct {
	Privileged bool        `yaml:"privileged"`
	SSH        *SSH        `yaml:"ssh"`
	WaitPort   *int        `yaml:"wait_port"`
	Commands   []string    `yaml:"commands"`
	Files      []FileCheck `yaml:"files"`
	Timezone   string      `yaml:"timezone"`
	Script     string      `yaml:"script"` // bash 逃生口：設了就只跑這支腳本
}

// LoadSpec 讀 path，回傳 service 合併 defaults 後的規格。
// service 有寫的欄位蓋過 defaults，明確寫 null 也算（用來關掉預設的 ssh）。
func LoadSpec(path, service string) (Spec, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return Spec{}, err
	}
	var doc struct {
		Defaults map[string]any            `yaml:"defaults"`
		Services map[string]map[string]any `yaml:"services"`
	}
	dec := yaml.NewDecoder(bytes.NewReader(raw))
	dec.KnownFields(true)
	if err := dec.Decode(&doc); err != nil {
		return Spec{}, fmt.Errorf("%s：%w", path, err)
	}
	svc, ok := doc.Services[service]
	if !ok {
		return Spec{}, fmt.Errorf("%s 沒有 service %q", path, service)
	}
	merged := map[string]any{}
	for k, v := range doc.Defaults {
		merged[k] = v
	}
	for k, v := range svc {
		merged[k] = v
	}
	b, err := yaml.Marshal(merged)
	if err != nil {
		return Spec{}, err
	}
	var s Spec
	d2 := yaml.NewDecoder(bytes.NewReader(b))
	d2.KnownFields(true)
	if err := d2.Decode(&s); err != nil {
		return Spec{}, fmt.Errorf("%s 的 %s：%w", path, service, err)
	}
	return s, nil
}

// RunArgs 組出啟動測試容器的 docker run 指令。
// 沒有 ssh、也沒有 wait_port 的容器可能啟動後就結束，所以改用 sleep 當 entrypoint 讓它活著。
// 有 wait_port 的容器（例如 filebrowser）是長駐主程序，照映像自己的 entrypoint 啟動。
func RunArgs(s Spec, image, name string) []string {
	args := []string{"docker", "run", "-d"}
	if s.Privileged {
		args = append(args, "--privileged")
	}
	args = append(args, "--name", name)
	if !NeedsIP(s) {
		return append(args, "--entrypoint", "sleep", image, "3600")
	}
	return append(args, image)
}

// Steps 把規格展開成依序執行的指令，每一步以 exit code 判定成敗。
// ip 是容器 IP（有 SSH 時才用），container 是容器名稱。
// ssh 只驗登入；command、檔案與時區一律走 docker exec（root，PATH 完整），
// 因為非互動 ssh 的 PATH 可能缺 /usr/local/bin，會誤報。
func Steps(s Spec, ip, container string) [][]string {
	if s.Script != "" {
		target := container
		if s.SSH != nil {
			target = ip
		}
		return [][]string{{"bash", s.Script, target}}
	}
	exec := func(remote string) []string {
		return []string{"docker", "exec", container, "sh", "-c", remote}
	}
	var steps [][]string
	if s.SSH != nil {
		steps = append(steps, []string{
			"sshpass", "-p", s.SSH.Password, "ssh",
			"-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
			s.SSH.User + "@" + ip, "echo ssh test ok",
		})
	}
	for _, c := range s.Commands {
		steps = append(steps, exec("command -v "+c))
	}
	for _, f := range s.Files {
		steps = append(steps, exec(fmt.Sprintf("test \"$(stat -c '%%a %%U' %s)\" = '%s %s'", f.Path, f.Mode, f.Owner)))
	}
	if s.Timezone != "" {
		steps = append(steps, exec(fmt.Sprintf("{ readlink /etc/localtime; cat /etc/timezone; } 2>/dev/null | grep -q %s", strconv.Quote(s.Timezone))))
	}
	return steps
}

// InspectIPArgs 組出取容器 IP 的 docker inspect 指令。
// 新版 Docker 不再提供頂層的 NetworkSettings.IPAddress，所以走 Networks；
// 模板每個網路輸出一行，由 FirstIP 取第一個非空的。
func InspectIPArgs(container string) []string {
	return []string{"docker", "inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{\"\\n\"}}{{end}}", container}
}

// FirstIP 從 InspectIPArgs 的輸出取第一個非空行；都空則回空字串。
func FirstIP(out string) string {
	for _, l := range strings.Split(out, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			return l
		}
	}
	return ""
}

// NeedsIP 表示這個規格要取容器 IP：要 ssh 登入，或要等埠。
func NeedsIP(s Spec) bool { return s.SSH != nil || s.WaitPort != nil }
