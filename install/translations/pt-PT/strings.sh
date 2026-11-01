# Português, Portugal (pt-PT)

TXT_INSTALLING_IN="A instalar em"
TXT_DONE="Concluído"
TXT_INSTALLED_RUNNING="instalado e a funcionar!

Reverta com acc -b se não estiver satisfeito."
TXT_REBOOT_UNNECESSARY="O reinício não é necessário."
TXT_REBOOT_NOTE="Nota: Se não reiniciar agora, coloque o prefixo /dev/ em todos os executáveis do acc (como em /dev/acc -i, /dev/accd).
Razão: O Magisk, KernelSU e semelhantes não fazem [re]mount/atualização de módulos sem um reinício."
TXT_NON_MAGISK_NOTICE="Os utilizadores sem Magisk podem ativar o início automático de $id executando /data/adb/$domain/$id/service.sh (uma cópia ou um link para o mesmo) - com init.d ou uma aplicação que o emule."
TXT_OVERLAY_SUPPORT="- Adicionar suporte para overlayfs"
TXT_RUNNING="[*] O daemon está atualmente A FUNCIONAR."
TXT_STOPPING="[*] A parar o accd..."
TXT_STOPPED="[*] Daemon PARADO."
TXT_STOPPED_STATE="[*] O daemon está atualmente PARADO."
TXT_STARTING="[*] A iniciar o accd..."
TXT_STARTED="[*] Daemon INICIADO."
TXT_TEST_RUNNING="[!] O Test All está a funcionar e requer que o daemon esteja parado."
TXT_WAIT_TEST="[!] Aguarde que termine (ou cancele-o) e tente novamente."
TXT_PROP_ERROR="[!] Erro: module.prop não encontrado em"
MODULE_DESC="Prolongue a vida útil da sua bateria controlando a corrente de carga, a temperatura e a tensão."

print_already_running() {
  echo "accd já está em execução"
}

print_started() {
  echo "accd foi iniciado"
}

print_stopped() {
  echo "accd foi parado"
}

print_not_running() {
  echo "accd não está em execução"
}

print_restarted() {
  echo "accd foi reiniciado"
}

print_is_running() {
  echo "accd $1 está em execução $2"
}

print_config_reset() {
  echo "A configuração padrão foi restaurada"
}

print_invalid_switch() {
  echo "Interruptor de carga inválido, [${chargingSwitch[@]-}]"
}

print_charging_disabled_until() {
  echo "Recarga desativada até % <= $1"
}

print_charging_disabled_for() {
  echo "Recarga desativada por $1"
}

print_charging_disabled() {
  echo "Recarga desativada"
}

print_charging_enabled_until() {
  echo "Recarga ativada até % >= $1"
}

print_charging_enabled_for() {
  echo "Recarga ativada por $1"
}

print_charging_enabled() {
  echo "Recarga ativada"
}

print_unplugged() {
  printf "Conecte o carregador primeiro 🔌\n\n"
}

print_switch_works() {
  echo "[$@] funciona"
}

print_switch_fails() {
  echo "[$@] não funciona"
}

print_not_found() {
  echo "$1 não encontrado"
}

#print_help() {

print_exit() {
  echo "Sair"
}

print_choice_prompt() {
  echo "(?) Introduza um número e clique [enter]: "
}

print_auto() {
  echo "Automático"
}

print_default() {
 echo "Predefinição"
}

print_curr_restored() {
  echo "Máxima corrente de recarga padrão restaurada"
}

print_volt_restored() {
  echo "Máxima voltagem padrão de recarga restaurada"
}

print_read_curr() {
  echo "Antes the prosseguir, o acc precisa obter os padrões máximos de corrente de recarga"
  print_unplugged
  echo -n "- À espera..."
}

print_curr_set() {
  echo "Máxima corrente de recarga definida para $1 miliamperes"
}

print_volt_set() {
  echo "Máxima voltagem de recarga definida para $1 milivolts"
}

print_curr_range() {
  echo "Apenas [$1] (miliamperes)"
}

print_volt_range() {
  echo "Apenas [$1] (milivolts)"
}
