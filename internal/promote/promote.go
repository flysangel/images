// Package promote 把驗證過的映像從 staging 複製到正式 registry。
package promote

import (
	"fmt"
	"strings"

	"github.com/flysangel/images/internal/registry"
)

// Promote 把 from（ref@digest）複製成 to，digest 保持不變。
// to 已存在就拒絕覆蓋；複製後兩邊 digest 不同也回錯。
func Promote(rc registry.Client, from, to string) error {
	exists, err := rc.Exists(to)
	if err != nil {
		return fmt.Errorf("檢查 %s 是否存在失敗：%w", to, err)
	}
	if exists {
		return fmt.Errorf("%s 已存在，拒絕覆蓋", tagOf(to))
	}
	if err := rc.Copy(from, to); err != nil {
		return fmt.Errorf("複製 %s 到 %s 失敗：%w", from, to, err)
	}
	src, err := rc.Digest(from)
	if err != nil {
		return err
	}
	dst, err := rc.Digest(to)
	if err != nil {
		return err
	}
	if src != dst {
		return fmt.Errorf("複製後 digest 不一致：來源 %s，目的 %s", src, dst)
	}
	return nil
}

// tagOf 取 ref 的 tag 部分；沒有 tag 時回整個 ref。
func tagOf(ref string) string {
	i := strings.LastIndex(ref, ":")
	if i > strings.LastIndex(ref, "/") {
		return ref[i+1:]
	}
	return ref
}
