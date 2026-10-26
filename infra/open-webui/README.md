# `infra/open-webui/` — Open WebUI dbadm 樣板

單 service：`dbadm`（open-webui 帳號管理 helper），FROM 上游 alpine。本 family 已遷到 `imgctl`：值在 `catalog.yaml`，煙霧測試在 `tests.yaml`，建置與測試由 `imgctl` 與 GitHub Actions 執行，不用 `img.sh`。

## 結構

```text
open-webui/
├── dbadm.Dockerfile          # FROM ${LIBRARY_ALPINE_IMAGE}
├── tests.yaml                # 煙霧測試：四支 helper 的權限與必要指令
├── adduser.sh                # COPY 進 image /bin/
├── deluser.sh
├── lsuser.sh
├── resetpasswd.sh
├── .imgctl                   # 已遷移標記
└── README.md
```

## 看值表

```bash
go run ./cmd/imgctl plan
```
