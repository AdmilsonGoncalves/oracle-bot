#!/bin/bash

# Função auxiliar para envio de mensagens ao Telegram
send_telegram() {
    local MESSAGE="$1"
    if [ ! -z "$TG_TOKEN" ] && [ ! -z "$TG_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -d "chat_id=${TG_CHAT_ID}" \
            -d "text=${MESSAGE}" > /dev/null
    fi
}

echo "=========================================================="
echo " Sniper ARM Inicializado - Testando Conexão com API OCI  "
echo "=========================================================="

if [ ! -f "/root/.oci/config" ]; then
    MSG="❌ ERRO FATAL: Arquivo de configuração da Oracle não encontrado em /root/.oci/config"
    echo "$MSG"
    send_telegram "$MSG"
    exit 1
fi

# Teste inicial de conexão/autenticação com a API OCI
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Testando autenticação com a API OCI..."
API_TEST_OUTPUT=$(oci iam region list 2>&1)
API_TEST_CODE=$?

if [ $API_TEST_CODE -ne 0 ]; then
    ERR_MSG="❌ ERRO DE CONEXÃO/API OCI: Falha ao autenticar na Oracle Cloud. Verifique suas chaves e config. Detalhes:
${API_TEST_OUTPUT}"
    echo "$ERR_MSG"
    send_telegram "$ERR_MSG"
    exit 1
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Conexão com API OCI autenticada com sucesso!"
    send_telegram "🤖 Sniper Oracle: Conexão com a API OCI testada e autenticada com sucesso! Monitorando vagas ARM (VM.Standard.A1.Flex)..."
fi

export SUPPRESS_LABEL_WARNING=True
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True

# Limpa possíveis aspas extras da variável SSH_PUBLIC_KEY e gera JSON válido via jq
CLEAN_SSH_KEY=$(echo "$SSH_PUBLIC_KEY" | sed -e 's/^"//' -e 's/"$//')
METADATA_JSON=$(jq -n -c --arg ssh "$CLEAN_SSH_KEY" '{ssh_authorized_keys: $ssh}')

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Disparando requisição de provisionamento..."

    # Executa a chamada do OCI CLI capturando stdout e stderr
    LAUNCH_OUTPUT=$(oci compute instance launch \
        --availability-domain "$OCI_AD" \
        --compartment-id "$OCI_COMPARTMENT" \
        --shape "VM.Standard.A1.Flex" \
        --shape-config '{"ocpus": 2, "memoryInGBs": 12}' \
        --subnet-id "$OCI_SUBNET" \
        --image-id "$OCI_IMAGE" \
        --boot-volume-size-in-gbs 200 \
        --assign-public-ip true \
        --metadata "$METADATA_JSON" \
        --display-name "$OCI_INSTANCE_NAME" 2>&1)

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo "=========================================================="
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCESSO! Instância criada."
        echo "$LAUNCH_OUTPUT"
        echo "=========================================================="
        
        # Alerta Sonoro no Laptop
        # shellcheck disable=SC2034
        for i in {1..5}; do echo -e '\a'; sleep 0.5; done
        
        # Disparo para o Telegram
        send_telegram "✅ SUCESSO! A sua instância ARM de 2 vCPUs e 12GB de RAM foi criada na Oracle Cloud de São Paulo! 🎉"
        break
    else
        # Verifica se é erro comum de falta de capacidade ou falha transitória de rede/API (timeout)
        if echo "$LAUNCH_OUTPUT" | grep -Ei "Out of host capacity|LimitExceeded|Capacity|InternalError|TooManyRequests|timed out|timeout|RequestException|ConnectionError|ServiceUnavailable|50[0-4]" > /dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sem capacidade ARM ou instabilidade temporária na API OCI (timeout). Nova tentativa em 60 segundos..."
        else
            # Erro inesperado (ex: parâmetro inválido, permissão, subnet incorreta)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Erro na requisição de criação:"
            echo "$LAUNCH_OUTPUT"
            send_telegram "⚠️ ERRO na criação da instância OCI (verifique os parâmetros no .env):
${LAUNCH_OUTPUT}"
        fi
        sleep 60
    fi
done
