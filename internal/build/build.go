// Package build 組出 buildx 與版本探測的指令，並解析上層映像的 digest。
// 指令只組不跑，執行由 cmd/imgctl 負責，所以不需要 docker 就能測。
package build

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/flysangel/images/internal/catalog"
	"github.com/flysangel/images/internal/dockerfile"
	"github.com/flysangel/images/internal/plan"
	"github.com/flysangel/images/internal/registry"
)

// StagingTag 是臨時 tag：`<service>-<sha>`。
func StagingTag(item plan.Item, sha string) string {
	return item.Service + "-" + sha
}

// Command 組出 docker buildx build 指令。
// parents 的鍵是 *_IMAGE ARG 名，值是 ref@digest；Item.Parents 列的每個上層都必須有。
func Command(item plan.Item, parents map[string]string, stagingRepo, sha string) ([]string, error) {
	args := map[string]string{}
	for k, v := range item.BuildArgs {
		args[k] = v
	}
	for k, v := range item.Upstream {
		args[k] = v
	}
	for _, p := range item.Parents {
		fam, svc, ok := strings.Cut(p, "/")
		if !ok {
			return nil, fmt.Errorf("plan 的上層格式不對：%q", p)
		}
		arg := dockerfile.ImageArgName(fam, svc)
		v, ok := parents[arg]
		if !ok || v == "" {
			return nil, fmt.Errorf("缺上層映像 %s（%s）", arg, p)
		}
		args[arg] = v
	}
	keys := make([]string, 0, len(args))
	for k := range args {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	cmd := []string{
		"docker", "buildx", "build", "--push", "--provenance=false",
		"--label", plan.HashLabel + "=" + item.InputHash,
		"-t", stagingRepo + "/" + item.Family + ":" + StagingTag(item, sha),
		"-f", "infra/" + item.Family + "/" + item.Service + ".Dockerfile",
	}
	for _, k := range keys {
		cmd = append(cmd, "--build-arg", k+"="+args[k])
	}
	return append(cmd, "infra/"+item.Family), nil
}

// ResolveParents 為 item 的每個本地上層找出 ref@digest。
// 本輪重建的上層：讀 dir 裡的 `<family>_<service>.ref`。
// 本輪沒重建的：用 plan 裡的 Tag 組 `<registry>/<family>:<tag>`，再查 digest 釘死。
func ResolveParents(item plan.Item, p *plan.Plan, dir, registryPrefix string, rc registry.Client) (map[string]string, error) {
	out := map[string]string{}
	for _, par := range item.Parents {
		fam, svc, _ := strings.Cut(par, "/")
		arg := dockerfile.ImageArgName(fam, svc)
		b, err := os.ReadFile(filepath.Join(dir, fam+"_"+svc+".ref"))
		if err == nil {
			out[arg] = strings.TrimSpace(string(b))
			continue
		}
		if !os.IsNotExist(err) {
			return nil, err
		}
		var tag string
		for _, batch := range p.Batches {
			for _, it := range batch {
				if it.Family == fam && it.Service == svc {
					tag = it.Tag
				}
			}
		}
		if tag == "" {
			return nil, fmt.Errorf("上層 %s 本輪沒有 ref 檔，plan 也沒有可用的 tag", par)
		}
		repo := registryPrefix + "/" + fam
		d, err := rc.Digest(repo + ":" + tag)
		if err != nil {
			return nil, fmt.Errorf("查 %s:%s 的 digest 失敗：%w", repo, tag, err)
		}
		out[arg] = repo + "@" + d
	}
	return out, nil
}

// ProbeCommand 組出查軟體版本的指令。回傳 tag.ParseVersionOutput 要用的 kind。
// 有 Command 用 command；否則 ubuntu 用 dpkg，其餘（alpine）用 apk。
func ProbeCommand(family string, vf *catalog.VersionFrom, image string) (string, []string, error) {
	if vf == nil {
		return "", nil, fmt.Errorf("service 沒有 version_from，無法探測版本")
	}
	base := []string{"docker", "run", "--rm", image}
	switch {
	case vf.Command != "":
		return "command", append(base, "sh", "-c", vf.Command), nil
	case vf.Package == "":
		return "", nil, fmt.Errorf("version_from 要設 package 或 command")
	case family == "ubuntu":
		return "dpkg", append(base, "dpkg-query", "-W", "-f=${Version}", vf.Package), nil
	}
	return "apk", append(base, "apk", "info", "-e", "-v", vf.Package), nil
}
