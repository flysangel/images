# `infra/fbs/` — Filebrowser 樣板

單 service：`base`（filebrowser web 介面），FROM `alpine:base`。本 family 已遷到 `imgctl`：值在 `catalog.yaml`，煙霧測試在 `tests.yaml`，建置與測試由 `imgctl` 與 GitHub Actions 執行，不用 `img.sh`。

## 結構

```text
fbs/
├── base.Dockerfile           # FROM ${ALPINE_BASE_IMAGE}
├── tests.yaml                # 煙霧測試：等 :4000 listen、檢查 filebrowser 在 PATH
├── docker_config.json        # filebrowser 預設設定；baked into image as /root/.filebrowser.json
├── .imgctl                   # 已遷移標記
└── README.md
```

⚠️ `docker_config.json` 內預設 `admin/admin` 帳密，僅 demo 用；runtime 應透過 env 或 volume 覆寫。

## 看值表

```bash
go run ./cmd/imgctl plan
```
