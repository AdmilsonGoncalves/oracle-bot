# Oracle ARM Sniper Bot 🤖

Sniper automatizado para monitorar e provisionar instâncias ARM gratuitas (`VM.Standard.A1.Flex` do Always Free Tier) na Oracle Cloud Infrastructure (OCI), com notificações em tempo real pelo Telegram e alerta sonoro.

---

## 🔒 Segurança e Estrutura do Projeto

Para garantir que nenhuma credencial ou chave privada vaze ao publicar este projeto no GitHub, o bot foi projetado para ler credenciais **externamente** ao diretório do repositório, no diretório seguro do sistema `/etc/opt/oracle-monitor`.

### Estrutura Externa Recomendada (`/etc/opt/oracle-monitor`)
```
/etc/opt/oracle-monitor/
├── .env                          # Variáveis de ambiente (Telegram e IDs da OCI)
└── .oci/                         # Diretório restrito (chmod 700)
    ├── config                    # Arquivo de configuração da OCI CLI
    ├── oci_api_key.pem           # Chave privada da API OCI (chmod 600)
    ├── ssh-key.key               # Chave privada SSH para acesso à VM (chmod 600)
    └── ssh-key.pub               # Chave pública SSH
```

> [!IMPORTANT]
> Nunca adicione arquivos `.env`, `.pem` ou `.key` dentro da pasta do projeto. O arquivo `.gitignore` já está configurado para bloquear esses arquivos por segurança.

---

## 📱 Tutorial 1: Como Configurar o Telegram Bot

Para receber alertas no Telegram quando a instância for criada ou em caso de erro na autenticação/parâmetros:

### 1. Criar o Bot e obter o Token (`TG_TOKEN`)
1. No Telegram, pesquise por **`@BotFather`** e inicie uma conversa.
2. Envie o comando `/newbot`.
3. Digite um nome para o seu bot (ex: `Oracle ARM Sniper`) e um nome de usuário terminando em `bot` (ex: `oracle_sniper_bot`).
4. O `@BotFather` retornará o **Token de Acesso** (ex: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`). Copie esse valor para a variável `TG_TOKEN` no seu `.env`.

### 2. Obter o seu ID de Chat (`TG_CHAT_ID`)
1. Pesquise pelo seu bot recém-criado no Telegram e envie uma mensagem qualquer para ele (ex: `Olá`).
2. Abra o navegador e acesse a seguinte URL (substituindo `<SEU_TOKEN>` pelo token obtido no passo anterior):
   ```
   https://api.telegram.org/bot<SEU_TOKEN>/getUpdates
   ```
3. No JSON retornado, procure pelo campo `"chat": {"id": 123456789}`.
4. Copie esse número e coloque na variável `TG_CHAT_ID` no seu `.env`.

---

## ☁️ Tutorial 2: Como Obter Credenciais e OCIDs da Oracle Cloud (OCI)

### 1. Chaves de API (`.oci/config` e `oci_api_key.pem`)
1. No painel web da Oracle Cloud, clique no seu ícone de perfil (canto superior direito) ➔ **My profile / Meu perfil**.
2. Vá na aba **API Keys / Chaves de API** (lado esquerdo) e clique em **Add API Key / Adicionar Chave de API**.
3. Selecione **Generate API Key Pair**, faça o download da chave privada (`oci_api_key.pem`) e salve em `/etc/opt/oracle-monitor/.oci/oci_api_key.pem`.
4. Ajuste a permissão da chave privada no terminal:
   ```bash
   chmod 600 /etc/opt/oracle-monitor/.oci/oci_api_key.pem
   ```
5. Clique em **Add**. A Oracle exibirá um bloco de texto de configuração (`[DEFAULT] user=...`). Copie esse bloco e salve no arquivo `/etc/opt/oracle-monitor/.oci/config`.
6. Certifique-se de que a linha `key_file` dentro do arquivo `config` aponte para o caminho interno no container Docker:
   ```ini
   key_file=/root/.oci/oci_api_key.pem
   ```

### 2. Informações da Instância (`/etc/opt/oracle-monitor/.env`)
Preencha o arquivo `/etc/opt/oracle-monitor/.env` com base no modelo `.env.example`:

* **`OCI_COMPARTMENT`**: OCID do seu Compartment ou Tenancy raiz. Disponível no menu **Identity & Security ➔ Compartments** (ou no seu perfil de Tenancy). Começa com `ocid1.tenancy.oc1...` ou `ocid1.compartment.oc1...`.
* **`OCI_AD`**: Nome técnico do Availability Domain (ex: `xxxx:SA-SAOPAULO-1-AD-1`). Pode ser consultado na tela de criação de instância ou via comando OCI CLI.
* **`OCI_SUBNET`**: OCID da sub-rede pública onde a VM será criada. Acesse **Networking ➔ Virtual Cloud Networks (VCN)** ➔ selecione sua VCN ➔ clique na sub-rede pública (ex: `public subnet-core-vcn`) e copie o OCID (`ocid1.subnet.oc1...`).
* **`OCI_IMAGE`**: OCID da imagem do sistema operacional. Para Ubuntu 24.04 ARM, consulte em **Compute ➔ Custom Images / Platform Images** e copie o OCID (`ocid1.image.oc1...`).
* **`OCI_INSTANCE_NAME`**: Nome desejado para a VM (ex: `horus`).
* **`SSH_PUBLIC_KEY`**: Conteúdo em texto plano da sua chave pública SSH (ex: `ssh-rsa AAAAB3Nza... user@host`). **Atenção:** Coloque sem aspas externas no arquivo `.env`.

---

## 🚀 Como Executar o Bot com Docker

### 1. Construir a Imagem Docker
No diretório do projeto (`oracle-bot`), execute:
```bash
docker build -t oracle-sniper .
```

### 2. Iniciar o Container em Segundo Plano
Execute o bot montando o diretório seguro de credenciais em `/etc/opt/oracle-monitor`:
```bash
docker run -d --name oracle-sniper \
  --restart unless-stopped \
  --env-file "/etc/opt/oracle-monitor/.env" \
  -v "/etc/opt/oracle-monitor/.oci:/root/.oci:ro" \
  oracle-sniper
```

### 3. Acompanhar os Logs do Bot
Para monitorar as requisições em tempo real:
```bash
docker logs -f oracle-sniper
```

---

## 🧠 Comportamento Inteligente do Bot

1. **Teste Inicial de Autenticação:** Ao iniciar, o bot testa a conexão com a API da Oracle Cloud. Se houver erro de chave ou configuração, ele alerta imediatamente no Telegram e encerra.
2. **Monitoramento Silencioso (`Out of host capacity`):** Como regiões concorridas (como São Paulo) costumam retornar falta de capacidade temporária, o bot identifica esse erro normal e **não envia spam** no Telegram. Ele tenta novamente a cada 60 segundos de forma silenciosa.
3. **Alerta de Sucesso:** Assim que a Oracle liberar capacidade e a instância for criada, o bot envia uma notificação de **✅ SUCESSO** no Telegram com os detalhes da instância e emite um alerta sonoro.
