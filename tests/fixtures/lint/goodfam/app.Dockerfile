# 多階段輔助層(兩段路徑無 tag,應跳過)+同家族前位+跨家族已宣告
FROM ${REGISTRY_PREFIX}/minio/mc AS mc
FROM ${REGISTRY_PREFIX}/goodfam:base-${SERVICE_VERSION}
FROM ${REGISTRY_PREFIX}/other:base-${OTHER_SERVICE_VERSION}
