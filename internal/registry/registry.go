// Package registry 包裝 go-containerregistry，提供 plan 與 build 需要的 registry 操作。
package registry

import (
	"errors"
	"net/http"

	"github.com/google/go-containerregistry/pkg/authn"
	"github.com/google/go-containerregistry/pkg/crane"
	"github.com/google/go-containerregistry/pkg/name"
	"github.com/google/go-containerregistry/pkg/v1/remote"
	"github.com/google/go-containerregistry/pkg/v1/remote/transport"
)

// Client 是 registry 操作的介面；plan 的測試用假實作取代。
type Client interface {
	// ListTags 列出 repo（不含 tag）的所有 tag。repo 不存在時回空清單。
	ListTags(repo string) ([]string, error)
	// Label 讀 ref 映像的 config label；沒有該 label 回空字串。
	Label(ref, key string) (string, error)
	// Digest 回傳 ref 的 digest（sha256:…）。
	Digest(ref string) (string, error)
	// Copy 把 src 原樣複製到 dst（digest 不變）。
	Copy(src, dst string) error
	// Exists 回傳 ref 是否存在。
	Exists(ref string) (bool, error)
}

type client struct {
	opts []remote.Option
}

// New 建立 Client。憑證走 authn.DefaultKeychain，讀不到時退回匿名。
func New(opts ...remote.Option) Client {
	all := append([]remote.Option{remote.WithAuthFromKeychain(authn.DefaultKeychain)}, opts...)
	return &client{opts: all}
}

// craneOpts 把 remote 選項轉成 crane 選項。
func (c *client) craneOpts() []crane.Option {
	return []crane.Option{crane.WithAuthFromKeychain(authn.DefaultKeychain), withRemote(c.opts)}
}

// withRemote 讓 crane 沿用同一組 remote 選項（含測試用的 transport）。
func withRemote(opts []remote.Option) crane.Option {
	return func(o *crane.Options) { o.Remote = append(o.Remote, opts...) }
}

func (c *client) ListTags(repo string) ([]string, error) {
	r, err := name.NewRepository(repo)
	if err != nil {
		return nil, err
	}
	tags, err := remote.List(r, c.opts...)
	if err != nil {
		if isNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	return tags, nil
}

func (c *client) Label(ref, key string) (string, error) {
	r, err := name.ParseReference(ref)
	if err != nil {
		return "", err
	}
	img, err := remote.Image(r, c.opts...)
	if err != nil {
		return "", err
	}
	cf, err := img.ConfigFile()
	if err != nil {
		return "", err
	}
	return cf.Config.Labels[key], nil
}

func (c *client) Digest(ref string) (string, error) {
	return crane.Digest(ref, c.craneOpts()...)
}

func (c *client) Copy(src, dst string) error {
	return crane.Copy(src, dst, c.craneOpts()...)
}

func (c *client) Exists(ref string) (bool, error) {
	r, err := name.ParseReference(ref)
	if err != nil {
		return false, err
	}
	_, err = remote.Head(r, c.opts...)
	if err != nil {
		if isNotFound(err) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// isNotFound 判斷錯誤是否表示 repo 或 tag 不存在：404，或 quay 對不存在 repo 回的
// 401 UNAUTHORIZED（匿名查不存在的 repo 時 quay 不回 404）。其他錯誤不算。
func isNotFound(err error) bool {
	var te *transport.Error
	if !errors.As(err, &te) {
		return false
	}
	if te.StatusCode == http.StatusNotFound {
		return true
	}
	if te.StatusCode != http.StatusUnauthorized {
		return false
	}
	for _, d := range te.Errors {
		if d.Code == transport.UnauthorizedErrorCode {
			return true
		}
	}
	return false
}
