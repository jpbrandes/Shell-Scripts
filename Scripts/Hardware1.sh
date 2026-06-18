#!/bin/bash

# AUTORIA: FÁBIO
# ============================================================
#   CANIVETE SUÍÇO — DIAGNÓSTICO PC
#   Para uso no Linux Mint Live Mode (pendrive)
#   Executar como root: sudo ./Verificacao.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Erro: Execute este script como root.${NC}"
  echo "Use: sudo ./tecnico.sh" # Esse bloco verifica se o script está sendo executado como root (sudo).
  exit 1
fi

echo -e "${YELLOW}Instalando ferramentas essenciais...${NC}"
sudo apt update -y
# FIX 3: adicionado lm-sensors para leitura real de temperatura
sudo apt install smartmontools ethtool ntfs-3g lm-sensors git gh -y # Esse bloco instala as ferramentas smartmontools, ethtool, ntfs-3g e lm-sensors

function pause() {
    read -p "Pressione [Enter] para continuar..."
}

# ============================================================
#   OPÇÃO 1 — DIAGNÓSTICO DE HARDWARE
# ============================================================

function diagnostico_hardware() {
    clear
    echo -e "${YELLOW}=== DIAGNÓSTICO COMPLETO DE HARDWARE ===${NC}\n"

    # 1. PROCESSADOR E PLACA-MÃE
    echo -e "${GREEN}[+] Verificando Processador e Placa-mãe (MCE Logs)...${NC}"
    MCE_ERRORS=$(dmesg | grep -iE "Machine Check|Hardware Error") # Esse linha busca as palavras Machine Check e Hardware Error, caso não tenha essas palavras, resulta em nenhum erro.
    if [ -z "$MCE_ERRORS" ]; then
        echo "Nenhum erro crítico de hardware encontrado."
    else
        echo -e "${RED}ALERTA: Erros de hardware detectados no processador/placa-mãe:${NC}"  
        echo "$MCE_ERRORS"
    fi
    echo ""

    # ──────────────────────────────────────────────────────
    # FIX 3 — TEMPERATURA DA CPU (lm-sensors + fallback inteligente)
    # Motivo: antes só lia a thermal_zone0, que pode ser da placa-mãe
    # ou da bateria, não da CPU. O lm-sensors lê os sensores reais
    # do chip (coretemp / k10temp). O fallback agora filtra apenas
    # zonas do tipo "x86_pkg_temp" ou "cpu-thermal" em vez de pegar
    # a primeira zona aleatória.
    # ──────────────────────────────────────────────────────
    echo -e "${GREEN}[+] Verificando Temperatura da CPU...${NC}"

    TEMP_FOUND=0

    # Tentativa 1: lm-sensors (mais preciso — lê núcleos individualmente)
    if command -v sensors &>/dev/null; then
        # Inicializa os módulos silenciosamente na primeira execução
        sensors-detect --auto &>/dev/null 2>&1 || true
        # Remove a parte entre parênteses (high/crit) antes de extrair a temperatura,
        # para não capturar os limiares como se fossem a leitura real.
        # Esse bloco utiliza a ferramenta da lm-sensors, analisando núcleo por núcleo.
        CPU_TEMPS=$(sensors 2>/dev/null \
            | grep -E "^(Core [0-9]|Tdie|Tctl|CPU Temp|Package id)" \ 
            | sed 's/([^)]*)//g' \
            | grep -oP '[+-]\d+\.\d+°C' \
            | grep -oP '\d+' )

        if [ -n "$CPU_TEMPS" ]; then
            MAX_TEMP=$(echo "$CPU_TEMPS" | sort -n | tail -1)
            echo "  Temperaturas via lm-sensors:"
            sensors 2>/dev/null \
                | grep -E "^(Core [0-9]|Tdie|Tctl|CPU Temp|Package id)" \ # Esses blocos a partir deste, apenas são uma média de temperatura, sendo acima de 90 crítico.
                | sed 's/^/    /'
            echo ""
            if [ "$MAX_TEMP" -ge 90 ]; then
                echo -e "${RED}  !! ESTAGIO 3 -- TEMPERATURA CRITICA: ${MAX_TEMP}C${NC}"
                echo -e "${RED}     Risco real de dano ao processador!${NC}"
                echo -e "${RED}     -> Desligue o computador imediatamente.${NC}"
                echo -e "${RED}     -> Verifique o cooler, pasta termica e ventilacao do gabinete.${NC}"
            elif [ "$MAX_TEMP" -ge 75 ]; then
                echo -e "${YELLOW}  !! ESTAGIO 2 -- TEMPERATURA ELEVADA: ${MAX_TEMP}C${NC}"
                echo -e "${YELLOW}     Acima do ideal, mas sem risco imediato.${NC}"
                echo -e "${YELLOW}     -> Verifique se o cooler esta girando corretamente.${NC}"
                echo -e "${YELLOW}     -> Considere reaplicar pasta termica e limpar o dissipador.${NC}"
            else
                echo -e "${GREEN}  OK ESTAGIO 1 -- TEMPERATURA NORMAL: ${MAX_TEMP}C${NC}"
                echo -e "${GREEN}     Processador operando na faixa ideal. Nenhuma acao necessaria.${NC}"
            fi
            TEMP_FOUND=1
        fi
    fi

    # Tentativa 2: /sys/class/thermal — filtra apenas zonas de CPU real
    if [ "$TEMP_FOUND" -eq 0 ]; then
        for zone_dir in /sys/class/thermal/thermal_zone*/; do
            zone_type=$(cat "${zone_dir}type" 2>/dev/null)
            # Aceita apenas zonas claramente de CPU
            if echo "$zone_type" | grep -qiE "x86_pkg_temp|cpu-thermal|coretemp|soc_thermal"; then
                raw_temp=$(cat "${zone_dir}temp" 2>/dev/null)
                if [ -n "$raw_temp" ] && [ "$raw_temp" -gt 0 ] 2>/dev/null; then
                    TEMP_C=$((raw_temp / 1000))
                    echo "  Zona: $zone_type → ${TEMP_C}°C"
                    if [ "$TEMP_C" -ge 90 ]; then
                        echo -e "${RED}  ALERTA: Temperatura crítica: ${TEMP_C}°C — Risco de dano!${NC}"
                    elif [ "$TEMP_C" -ge 75 ]; then
                        echo -e "${YELLOW}  AVISO: Temperatura elevada: ${TEMP_C}°C — Verificar cooler.${NC}"
                    fi
                    TEMP_FOUND=1 # Vê as temperaturas do CPU.
                fi
            fi
        done
    fi

    # Tentativa 3: hwmon — busca entradas "temp*_input" com label de CPU
    if [ "$TEMP_FOUND" -eq 0 ]; then
        for hwmon_dir in /sys/class/hwmon/hwmon*/; do
            hwmon_name=$(cat "${hwmon_dir}name" 2>/dev/null)
            if echo "$hwmon_name" | grep -qiE "coretemp|k10temp|nct|it87"; then
                for temp_input in "${hwmon_dir}"temp*_input; do
                    [ -f "$temp_input" ] || continue
                    raw=$(cat "$temp_input" 2>/dev/null)
                    [ -n "$raw" ] || continue
                    TEMP_C=$((raw / 1000))
                    label_file="${temp_input/_input/_label}"
                    label=$(cat "$label_file" 2>/dev/null || echo "sensor")
                    echo "  [$hwmon_name] $label → ${TEMP_C}°C"
                    TEMP_FOUND=1
                done # Esse bloco acima, aparentemente identifica o rótulo do processador.
            fi
        done
    fi

    if [ "$TEMP_FOUND" -eq 0 ]; then
        echo "  Nenhum sensor de CPU encontrado neste hardware."
        echo -e "${CYAN}  Dica: alguns modelos não expõem temperatura via software.${NC}"
    fi
    echo ""

    # 3. DISCOS (S.M.A.R.T.)
    echo -e "${GREEN}[+] Verificando Saúde dos HDs/SSDs (S.M.A.R.T.)...${NC}"
    DRIVES=$(lsblk -nd -o NAME | grep -E "^sd|^nvme")
    if [ -z "$DRIVES" ]; then
        echo "Nenhum disco detectado." # Verifica a existência de disco
    else
        while IFS= read -r drive; do
            echo -e "${CYAN}  Testando /dev/$drive:${NC}"
            smartctl -H "/dev/$drive" | grep -E "test result|SMART overall" \
                || echo -e "${RED}  Falha ao ler SMART de /dev/$drive.${NC}"
        done <<< "$DRIVES"
    fi
    echo ""

    # 4. PORTAS USB
    echo -e "${GREEN}[+] Verificando erros em portas USB...${NC}"
    USB_ERRORS=$(dmesg | grep -i usb | grep -iE "error|fail|cannot enumerate|over-current") # PALAVRAS CHAVE, caso o dmesg retorne alguma dessas palavras, existe erro nas portas USB.
    if [ -z "$USB_ERRORS" ]; then
        echo "Nenhum erro elétrico ou de comunicação USB detectado."
    else
        echo -e "${RED}ALERTA: Problemas detectados nas portas/dispositivos USB:${NC}"
        echo "$USB_ERRORS" | tail -n 5
    fi
    echo ""

    # 5. REDE
    echo -e "${GREEN}[+] Verificando Interfaces de Rede...${NC}"
    NET_ERRORS=$(dmesg | grep -iE "eth0|enp|wlan|net" | grep -iE "error|fail|down|link is not ready") # PALAVRAS CHAVE novamente, caso haja alguma dessas palavras, existem erros de rede.
    if [ -z "$NET_ERRORS" ]; then
        echo "Nenhum erro crítico de driver ou hardware de rede detectado." 
    else
        echo -e "${RED}Avisos de rede encontrados (cabo solto ou placa falhando):${NC}"
        echo "$NET_ERRORS" | tail -n 5
    fi
    echo ""

    # ──────────────────────────────────────────────────────
    # FIX 2 — MEMÓRIA RAM (filtro cirúrgico)
    # Motivo: "memory error" batia em mensagens normais como
    # "Correcting memory error" (log informativo) ou "memory error
    # recovery" (mensagem de driver). Agora o filtro exige termos
    # específicos de falha real de hardware de RAM (EDAC com CE/UE,
    # ou erros MCE categorizados como memória).
    # ──────────────────────────────────────────────────────
    echo -e "${GREEN}[+] Verificando Memória RAM (Logs do sistema)...${NC}"
    RAM_ERRORS=$(dmesg | grep -iE \
        "EDAC.*(CE|UE|error|corrected|uncorrected)" \
        | grep -viE "no.*error|0 error|cleared|reset")

    # Complemento: erros MCE classificados como memória
    MCE_MEM=$(dmesg | grep -iE "Machine Check.*mem|mce.*DRAM|mce.*bank.*[0-9]" \
        | grep -viE "corrected.*0|no error")

    ALL_RAM_ERRORS=$(printf "%s\n%s" "$RAM_ERRORS" "$MCE_MEM" | grep -v "^$")

    if [ -z "$ALL_RAM_ERRORS" ]; then
        echo "Nenhum erro de memória detectado nos logs."
        echo -e "${CYAN}  Dica: Para teste 100% confiável de RAM, use o MemTest86+ no boot.${NC}" # Esse bloco checa a memória ram e procura novamente palavras chaves com dmesg e grep.
    else
        echo -e "${RED}ALERTA: Falhas de módulo de memória registradas!${NC}"
        echo "$ALL_RAM_ERRORS"
    fi
    echo ""
    pause
}

# ============================================================
#   OPÇÃO 2 — REPARO DE PARTIÇÃO DO HD
# ============================================================

function reparo_sistema() {
    clear
    echo -e "${YELLOW}=== REPARO DE PARTIÇÃO DO HD ===${NC}"
    echo ""
    echo "Como funciona:"
    echo "  O Linux Mint está rodando pelo pendrive na memória RAM."
    echo "  Por isso o HD do computador está livre e pode ser reparado."
    echo "  O reparo corrige a organização lógica dos arquivos (inodes,"
    echo "  diretórios órfãos, mapa de blocos) sem apagar seus dados."
    echo ""

    BOOT_DEVICE=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /) 2>/dev/null)

    echo -e "${CYAN}Dispositivos encontrados neste computador:${NC}"
    echo "──────────────────────────────────────────────────────────────"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL | grep -E "disk|part"
    echo "──────────────────────────────────────────────────────────────"
    echo ""

    if [ -n "$BOOT_DEVICE" ]; then
        echo -e "${RED}⛔  NÃO repare: /dev/$BOOT_DEVICE — este é o seu PENDRIVE LIVE${NC}" # É importante prestar atenção aqui, caso não haja atenção necessária é possível apagar o pendrive bootável.
        echo ""
    fi

    echo -e "${GREEN}Partições do HD disponíveis para reparo:${NC}"
    lsblk -p -o NAME,FSTYPE,SIZE,MOUNTPOINT \
        | grep -E "ext2|ext3|ext4|ntfs" \
        | { [ -n "$BOOT_DEVICE" ] && grep -v "$BOOT_DEVICE" || cat; }
    echo ""

    read -p "Digite a partição do HD para reparar (Ex: /dev/sda1) ou 'sair': " TARGET_PART 
    [ "$TARGET_PART" = "sair" ] && return

    # Partições em discos Linux são organizados com números.
    # Se sda é o disco principal, as partições dele são dadas como sda1,sda2... É preciso se atentar com a partição correta. Uma forma de identifcar elas é pelo MOUNTPOINT e pelo tamanho em armazenamento.

    # ──────────────────────────────────────────────────────
    # FIX 1 — BLOQUEIO DO PENDRIVE
    # Motivo: quando $BOOT_DEVICE era vazio (ex: sistema não detectou
    # o pendrive corretamente), `grep -q ""` sempre retornava verdadeiro,
    # bloqueando QUALQUER partição que o usuário digitasse.
    # Correção: só executa o bloqueio se $BOOT_DEVICE não for vazio,
    # e ancora o grep no início do nome do dispositivo para evitar
    # falsos positivos (ex: "sdb" não deve bloquear "sda" ou "sdbc").
    # ──────────────────────────────────────────────────────
    if [ -n "$BOOT_DEVICE" ] && echo "$TARGET_PART" | grep -qE "/dev/${BOOT_DEVICE}(p?[0-9]+)?$"; then
        echo ""
        echo -e "${RED}⛔  BLOQUEADO: Você digitou o pendrive live — operação cancelada.${NC}"
        echo "    Digite a partição do HD (geralmente /dev/sda1)." # Proteção contra formatação do pendrive bootável.
        pause
        return
    fi

    if [ ! -b "$TARGET_PART" ]; then
        echo -e "${RED}Partição '$TARGET_PART' não encontrada. Verifique o nome digitado.${NC}"
        pause
        return # Protege contra partições inexistentes.
    fi

    FSTYPE=$(blkid -o value -s TYPE "$TARGET_PART" 2>/dev/null)
    echo ""
    echo -e "${CYAN}Partição: $TARGET_PART | Sistema de arquivos: $FSTYPE${NC}"
    echo ""

    read -p "Confirmar reparo em $TARGET_PART? (s/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then # Bloco da operação de reparo
        echo "Operação cancelada."
        pause
        return
    fi

    if mount | grep -q "$TARGET_PART"; then
        echo -e "${YELLOW}Partição montada. Desmontando para o reparo...${NC}"
        umount "$TARGET_PART" || {
            echo -e "${RED}Falha ao desmontar. Tente reiniciar o live mode e rodar o script novamente.${NC}" # Segundo bloco da operação de reparo
            pause
            return
        }
    fi

    echo ""

    case "$FSTYPE" in
        ext2|ext3|ext4)
            echo -e "${GREEN}Iniciando reparo em $TARGET_PART ($FSTYPE)...${NC}" # Operação de reparo
            echo "O que está acontecendo agora:"
            echo "  Etapa 1/5 — Verificando inodes (fichas de cada arquivo)"
            echo "  Etapa 2/5 — Verificando diretórios"
            echo "  Etapa 3/5 — Verificando conectividade das pastas"
            echo "  Etapa 4/5 — Verificando contagem de referências"
            echo "  Etapa 5/5 — Verificando mapa de blocos livres"
            echo ""
            fsck -y -C0 "$TARGET_PART"
            ;;
        ntfs)
            echo -e "${GREEN}Iniciando reparo em $TARGET_PART (NTFS)...${NC}"
            echo "O ntfsfix vai:"
            echo "  → Limpar o flag de 'volume sujo' da partição"
            echo "  → Corrigir inconsistências básicas na tabela NTFS"
            echo "  → Preparar a partição para uso normal no Linux Mint"
            echo ""
            ntfsfix "$TARGET_PART"
            ;;
        "")
            echo -e "${RED}Não foi possível detectar o sistema de arquivos de $TARGET_PART.${NC}"
            echo "O disco pode estar sem formatação ou com tabela de partição danificada."
            ;;
        *)
            echo -e "${RED}Sistema de arquivos '$FSTYPE' não suportado para reparo automático.${NC}"
            echo "Sistemas suportados: ext2, ext3, ext4, ntfs."
            ;;
    esac

    echo ""
    echo -e "${GREEN}Processo de reparo finalizado em $TARGET_PART.${NC}"
    pause
}

# ============================================================
#   MENU PRINCIPAL
# ============================================================

while true; do
    clear
    echo -e "${YELLOW}╔══════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║     PROGRAMA ANTI GAP — DIAGNÓSTICO PC   ║${NC}"
    echo -e "${YELLOW}║         Linux Mint Live Mode             ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1. Diagnóstico Completo de Hardware"
    echo "  2. Reparar Partição Corrompida do HD"
    echo "  3. Sair"
    echo ""
    read -p "Escolha uma opção [1-3]: " OPCAO

    case $OPCAO in
        1) diagnostico_hardware ;;
        2) reparo_sistema ;;
        3) echo "Saindo..."; exit 0 ;;
        *) echo -e "${RED}Opção inválida!${NC}"; pause ;;
    esac
done
