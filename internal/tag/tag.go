// Package tag 是映像 tag 規則：版本字串轉換與下一個 tag 的決定。
// 全是純函式，不依賴其他 internal 套件。
package tag

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

var (
	unsafeChars = regexp.MustCompile(`[^A-Za-z0-9_.-]`)
	apkRevision = regexp.MustCompile(`-r\d+$`)
	apkVersion  = regexp.MustCompile(`-(\d[^-]*)$`)
	cmdVersion  = regexp.MustCompile(`v?(\d+(?:\.\d+)+)`)
	semverTag   = regexp.MustCompile(`^v(\d+)\.(\d+)\.(\d+)$`)
	revSuffix   = regexp.MustCompile(`^-r(\d+)$`)
)

// Sanitize 把 tag 不允許的字元（`[A-Za-z0-9_.-]` 以外）換成 `_`。
func Sanitize(raw string) string {
	return unsafeChars.ReplaceAllString(raw, "_")
}

// ParseVersionOutput 從版本查詢指令的輸出取出軟體版本。
// kind 為 "apk"（`apk info -e -v` 輸出）、"dpkg"（dpkg-query 的 Version）或 "command"。
// 回傳值尚未 Sanitize，由呼叫端處理。
func ParseVersionOutput(kind, out string) (string, error) {
	s := strings.TrimSpace(out)
	switch kind {
	case "apk":
		s = apkRevision.ReplaceAllString(s, "")
		m := apkVersion.FindStringSubmatch(s)
		if m == nil {
			return "", fmt.Errorf("apk 輸出找不到版本：%q", out)
		}
		return m[1], nil
	case "dpkg":
		if i := strings.Index(s, ":"); i >= 0 && isDigits(s[:i]) {
			s = s[i+1:]
		}
		if i := strings.LastIndex(s, "-"); i >= 0 {
			s = s[:i]
		}
		if s == "" {
			return "", fmt.Errorf("dpkg 輸出找不到版本：%q", out)
		}
		return s, nil
	case "command":
		m := cmdVersion.FindStringSubmatch(s)
		if m == nil {
			return "", fmt.Errorf("指令輸出找不到版本：%q", out)
		}
		return m[1], nil
	}
	return "", fmt.Errorf("未知的版本來源類型：%q", kind)
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// Next 依類別算出下一個 tag。
// 甲、乙：`<service>-<ver>`，已存在則接最大 `-rN` 之後（`-r2` 起）。
// 丙：取 `<service>-vX.Y.Z` 最大者，patch+1；bumpMinor 時 minor+1、patch 歸 0。
func Next(class, service, softwareVersion string, existing []string, bumpMinor bool) (string, error) {
	switch class {
	case "A", "B":
		return nextRevision(service, softwareVersion, existing), nil
	case "C":
		return nextSemver(service, existing, bumpMinor)
	}
	return "", fmt.Errorf("未知的類別：%q", class)
}

func nextRevision(service, ver string, existing []string) string {
	base := service + "-" + ver
	found := false
	maxRev := 1
	for _, t := range existing {
		if t == base {
			found = true
			continue
		}
		rest, ok := strings.CutPrefix(t, base)
		if !ok {
			continue
		}
		m := revSuffix.FindStringSubmatch(rest)
		if m == nil {
			continue
		}
		n, err := strconv.Atoi(m[1])
		if err != nil {
			continue
		}
		found = true
		if n > maxRev {
			maxRev = n
		}
	}
	if !found {
		return base
	}
	return fmt.Sprintf("%s-r%d", base, maxRev+1)
}

func nextSemver(service string, existing []string, bumpMinor bool) (string, error) {
	var best [3]int
	have := false
	for _, t := range existing {
		rest, ok := strings.CutPrefix(t, service+"-")
		if !ok {
			continue
		}
		m := semverTag.FindStringSubmatch(rest)
		if m == nil {
			continue
		}
		var v [3]int
		for i := range v {
			v[i], _ = strconv.Atoi(m[i+1])
		}
		if !have || greater(v, best) {
			best, have = v, true
		}
	}
	if !have {
		return "", fmt.Errorf("%s 沒有任何既有的 vX.Y.Z 版號", service)
	}
	if bumpMinor {
		best[1]++
		best[2] = 0
	} else {
		best[2]++
	}
	return fmt.Sprintf("%s-v%d.%d.%d", service, best[0], best[1], best[2]), nil
}

func greater(a, b [3]int) bool {
	for i := range a {
		if a[i] != b[i] {
			return a[i] > b[i]
		}
	}
	return false
}
