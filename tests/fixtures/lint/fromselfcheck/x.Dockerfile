# 名段含 '.'：FROM_CANDIDATE_RE 的 [^/\s]+ 收得下,FROM_REF_RE 的 [A-Za-z0-9_-]+ 收不下
# → 候選數 1、匹配數 0，正是自我檢查要抓的形態
FROM ${REGISTRY_PREFIX}/my.svc:base-${SERVICE_VERSION}
