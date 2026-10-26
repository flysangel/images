#!/bin/bash
# guacamole-ext.sh — 依 images/ 目錄下每個 logo 圖檔各自產生一份客製化 guacamole extension jar
# 做法:manifest/CSS 內的 LOGO 佔位字串先換成實際檔名、打包成 ext.jar,再把佔位字串換回 LOGO 供下一輪使用

#set -x # debug mode
mkdir -p ${GUACAMOLE_HOME}/guacamole-ext
mkdir -p ${GUACAMOLE_HOME}/ext/images

# 逐一處理 images/ 目錄下的 logo 圖檔(圖示包來源見下列連結)
# https://www.flaticon.com/packs/greek-mythology-47
for LOGO in $(ls ${GUACAMOLE_HOME}/images); do
  # 準備:複製 logo 圖檔,並把 manifest/CSS 內的 LOGO 佔位字串換成實際檔名
  cp -r ${GUACAMOLE_HOME}/images/${LOGO} ${GUACAMOLE_HOME}/ext/images
  sed -i "s|LOGO|${LOGO}|g" ${GUACAMOLE_HOME}/ext/guac-manifest.json
  sed -i "s|LOGO|${LOGO}|g" ${GUACAMOLE_HOME}/ext/css/login-override.css

  # 打包成 ext.jar(以 logo 檔名命名)
  jar cvf ${GUACAMOLE_HOME}/guacamole-ext/${LOGO}.jar -C ${GUACAMOLE_HOME}/ext .

  # 還原:清掉暫存的 logo 圖檔,並把 manifest/CSS 佔位字串換回 LOGO,供下一輪使用
  # 還原是全域字串替換：目錄名不得是 manifest 或 css 內會出現的字串（gmm、images、png、css），否則樣板會被改壞
  rm -rf ${GUACAMOLE_HOME}/ext/images/${LOGO}
  sed -i "s|${LOGO}|LOGO|g" ${GUACAMOLE_HOME}/ext/guac-manifest.json
  sed -i "s|${LOGO}|LOGO|g" ${GUACAMOLE_HOME}/ext/css/login-override.css
done
