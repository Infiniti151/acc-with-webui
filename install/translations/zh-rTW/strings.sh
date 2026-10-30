# 繁體中文 (zh-rTW)

TXT_INSTALLING_IN="正在安裝至"
TXT_DONE="完成"
TXT_INSTALLED_RUNNING="安裝成功並正在執行！

如果不滿意，請使用 acc -b 還原。"
TXT_REBOOT_UNNECESSARY="無需重新開機。"
TXT_REBOOT_NOTE="注意：如果不立即重新開機，請在所有 acc 可執行檔前加上 /dev/ 字首（例如 /dev/acc -i, /dev/accd）。
原因：Magisk、KernelSU 及類似工具在不重新開機的情況下不會[重新]掛載/更新模組。"
TXT_NON_MAGISK_NOTICE="非 Magisk 使用者可以透過執行 /data/adb/$domain/$id/service.sh（其複本或符號連結）來啟用 $id 自動啟動 - 可使用 init.d 或模擬該功能的應用程式。"
TXT_OVERLAY_SUPPORT="- 新增 overlayfs 支援"
TXT_RUNNING="[*] 幕後程式目前正在執行。"
TXT_STOPPING="[*] 正在停止 accd..."
TXT_STOPPED="[*] 幕後程式已停止。"
TXT_STOPPED_STATE="[*] 幕後程式目前已停止。"
TXT_STARTING="[*] 正在啟動 accd..."
TXT_STARTED="[*] 幕後程式已啟動。"
TXT_TEST_RUNNING="[!] 全面測試（Test All）正在執行，需要先停止幕後程式。"
TXT_WAIT_TEST="[!] 請等待其完成（或取消），然後重試。"
TXT_PROP_ERROR="[!] 錯誤：未在以下位置找到 module.prop："
MODULE_NAME="透過控制充電電流、溫度和電壓來延長電池的使用壽命。"

print_already_running() {
  echo "accd 目前是執行狀態"
}

print_started() {
  echo "accd 已啟動"
}

print_stopped() {
  echo "accd 已停止"
}

print_not_running() {
  echo "accd 目前沒有執行"
}

print_restarted() {
  echo "accd 以重啟"
}

print_is_running() {
  echo "accd $1 正在執行 $2"
}

print_config_reset() {
  echo "設定已重製"
}

print_invalid_switch() {
  echo "無效的充電開關, [${chargingSwitch[@]-}]"
}

print_charging_disabled_until() {
  echo "電量高於 $1 時停止充電"
}

print_charging_disabled_for() {
  echo "停止充電 $1"
}

print_charging_disabled() {
  echo "已停止充電"
}

print_charging_enabled_until() {
  echo "電量高於 $1 時繼續充電"
}

print_charging_enabled_for() {
  echo "開始充電 $1"
}

print_charging_enabled() {
  echo "已開始充電"
}

print_switch_works() {
  echo "[$@] 可用"
}

print_switch_fails() {
  echo "[$@] 不可用"
}

print_not_found() {
  echo "未找到 $1 目錄"
}

#print_help() {

print_exit() {
  echo "離開"
}

print_choice_prompt() {
  echo "(?) 請選擇, 確認鍵結束: "
}

print_auto() {
  echo "自動"
}

print_default() {
 echo "預設"
}
