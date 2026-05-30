# Workshop AWS — Site com Alta Disponibilidade usando S3 + EC2 + ASG + ALB

---

## Objetivo

Subir uma aplicação web estática na AWS utilizando:

- Amazon S3
- IAM Role
- EC2 (Amazon Linux 2023)
- Auto Scaling Group (ASG)
- Application Load Balancer (ALB)
- Nginx
- UserData automatizado

O objetivo do workshop **não é ensinar Linux**.

O foco é:

- Automação de infraestrutura
- Alta disponibilidade
- Escalabilidade automática
- Load Balancing
- Arquitetura AWS na prática

---

## Arquitetura Final

```
Usuário
   ↓
Application Load Balancer (ALB)  ← ponto de entrada único
   ↓
Auto Scaling Group (ASG)         ← mantém instâncias saudáveis
   ↓
EC2 Amazon Linux 2023            ← executa a aplicação
   ↓
UserData automatizado            ← bootstrap sem intervenção manual
   ↓
Coleta metadados da instância    ← instance-id, AZ, IPs, região
   ↓
Baixa arquivos do S3             ← site centralizado no bucket
   ↓
Injeta metadados no index.html   ← cada instância exibe seus próprios dados
   ↓
Nginx publica o site             ← serve na porta 80
```

---

## O que o site demonstra

Ao acessar o DNS do ALB e atualizar a página, o visitante vê:

- O **Instance ID** da EC2 que respondeu
- O **tipo da instância**
- O **IP público e privado**
- A **Availability Zone**
- A **Região**

Cada refresh pode cair em uma instância diferente, demonstrando o load balancing em tempo real.

---

## Fluxo da Demonstração

1. Upload do site no S3
2. Criação da IAM Role
3. Criação dos Security Groups
4. Criação do Launch Template com UserData
5. Criação do Auto Scaling Group
6. Criação automática do ALB
7. Instâncias ficam `InService` no Target Group
8. Acesso via DNS do Load Balancer
9. Refresh mostra mudança de instâncias (instance-id e AZ mudam)

---

## Estrutura do Projeto

Arquivos do site:

```
index.html
app.js
style.css
img/
  Logo UG ofc sem-fundo.png
```

Como deve ficar no bucket S3:

```
s3://meu-site-workshop/
    index.html
    app.js
    style.css
    img/
        Logo UG ofc sem-fundo.png
```

> **IMPORTANTE:** Os arquivos devem ficar na **raiz do bucket**, não dentro de subpastas.

---

## Como o UserData funciona

O script `userdata.sh` executa automaticamente na primeira inicialização de cada instância EC2. Ele:

1. Atualiza o sistema operacional
2. Instala nginx e aws-cli
3. Baixa os arquivos do S3 para `/usr/share/nginx/html`
4. Coleta os metadados da instância via **IMDSv2** (Instance Metadata Service)
5. Injeta os metadados nas `<meta>` tags do `index.html` usando `sed`
6. Ajusta permissões dos arquivos
7. Inicia o nginx
8. Valida que o site responde localmente

Sem a etapa de injeção dos metadados, o site exibiria "Nenhuma instância conectada" para todos os visitantes.

---

# ETAPA 1 — Criar Bucket S3

## Abrir S3

```
AWS Console → Services → S3
```

---

## Criar Bucket

Nome:

```
meu-site-workshop
```

Configurações obrigatórias:

- **Block Public Access:** habilitado (bucket privado)
- **ACLs:** desabilitadas
- **Versioning:** não é necessário para o workshop

> **IMPORTANTE:** Não deixe o bucket público. A EC2 acessa o S3 usando a IAM Role, sem necessidade de acesso público.

---

## Upload dos Arquivos

Entrar no bucket e clicar em **Upload**.

Enviar:

- `index.html`
- `app.js`
- `style.css`
- pasta `img/` (com a imagem do logo)

Após o upload, validar que os arquivos aparecem na **raiz do bucket** (não dentro de subpastas).

Para validar via CLI:

```bash
aws s3 ls s3://meu-site-workshop/
```

A saída esperada:

```
PRE img/
   app.js
   index.html
   style.css
```

---

# ETAPA 2 — Criar IAM Role da EC2

## Abrir IAM

```
AWS Console → Services → IAM → Roles → Create role
```

---

## Configurar a Role

| Campo | Valor |
|---|---|
| Trusted entity type | AWS service |
| Use case | EC2 |

---

## Adicionar Permissão

Buscar e adicionar a policy:

```
AmazonS3ReadOnlyAccess
```

> **Nota:** Para o workshop, `AmazonS3ReadOnlyAccess` é suficiente e mais seguro que `FullAccess`. A EC2 só precisa **ler** os arquivos do bucket.

---

## Nome da Role

```
EC2-S3-Role
```

Criar a role.

---

# ETAPA 3 — Criar Security Groups

Os Security Groups controlam quem pode falar com quem. A arquitetura correta é:

```
Internet → ALB (porta 80 aberta) → EC2 (porta 80 só do ALB)
```

A EC2 **nunca** deve receber tráfego direto da internet.

---

## Security Group do ALB

```
EC2 → Security Groups → Create security group
```

| Campo | Valor |
|---|---|
| Nome | alb-sg |
| Descrição | Security group do Application Load Balancer |
| VPC | VPC default |

**Inbound Rules:**

| Tipo | Protocolo | Porta | Origem |
|---|---|---|---|
| HTTP | TCP | 80 | 0.0.0.0/0 |

**Outbound Rules:** manter padrão (All traffic).

---

## Security Group da EC2

```
EC2 → Security Groups → Create security group
```

| Campo | Valor |
|---|---|
| Nome | ec2-sg |
| Descrição | Security group das instâncias EC2 |
| VPC | VPC default |

**Inbound Rules:**

| Tipo | Protocolo | Porta | Origem |
|---|---|---|---|
| HTTP | TCP | 80 | **alb-sg** (selecionar o SG, não um IP) |

> **IMPORTANTE:** Na origem, selecione o **Security Group** `alb-sg`, não `0.0.0.0/0`. Isso garante que apenas o ALB consiga acessar as instâncias.

**Outbound Rules:** manter padrão (All traffic — necessário para a EC2 acessar o S3 e o IMDS).

---

# ETAPA 4 — Criar Launch Template

O Launch Template define a configuração de cada instância que o ASG vai criar.

```
EC2 → Launch Templates → Create launch template
```

---

## Configurações Gerais

| Campo | Valor |
|---|---|
| Nome | lt-workshop-site |
| Descrição | Launch template para o workshop de alta disponibilidade |

---

## Amazon Machine Image (AMI)

Selecionar:

```
Amazon Linux 2023 AMI
```

> Use a versão mais recente disponível na sua região.

---

## Instance Type

```
t2.micro
```

---

## Key Pair

```
Proceed without key pair
```

O objetivo é automação total. Não precisamos de acesso SSH.

---

## Network Settings

| Campo | Valor |
|---|---|
| Security group | alb-sg |

---

## Storage

| Tipo | Tamanho |
|---|---|
| gp3 | 8 GB (padrão é suficiente) |

---

## Advanced Details

### IAM Instance Profile

Selecionar:

```
EC2-S3-Role
```

> **CRÍTICO:** Sem a IAM Role, o `aws s3 cp` no UserData vai falhar com erro de credenciais.

### User Data

Colar o script abaixo **exatamente como está**, sem modificações:

---

## USERDATA COMPLETO

```bash
#!/bin/bash

#########################################################
# CONFIGURAÇÕES
#########################################################

BUCKET_NAME="meu-site-workshop"
WEB_ROOT="/usr/share/nginx/html"
LOG_FILE="/var/log/user-data.log"

#########################################################
# LOGS
#########################################################

exec > >(tee -a $LOG_FILE | logger -t user-data -s 2>/dev/console) 2>&1

echo "=================================================="
echo "INICIANDO USER DATA"
echo "HORARIO: $(date)"
echo "=================================================="

#########################################################
# FUNÇÃO DE ERRO
#########################################################

error_exit () {
    echo "ERRO: $1"
    exit 1
}

#########################################################
# ATUALIZA SISTEMA
#########################################################

echo "Atualizando pacotes do sistema..."

dnf update -y || error_exit "Falha ao atualizar sistema"

#########################################################
# INSTALA PACOTES NECESSÁRIOS
#########################################################

echo "Instalando nginx e aws-cli..."

dnf install -y nginx aws-cli || error_exit "Falha ao instalar pacotes"

#########################################################
# HABILITA NGINX
#########################################################

echo "Habilitando nginx no boot..."

systemctl enable nginx || error_exit "Falha ao habilitar nginx"

#########################################################
# LIMPA DIRETÓRIO WEB
#########################################################

echo "Limpando diretório web..."

rm -rf ${WEB_ROOT:?}/* || error_exit "Falha ao limpar diretório web"

#########################################################
# BAIXA SITE DO S3
#########################################################

echo "Baixando arquivos do S3..."

aws s3 cp s3://${BUCKET_NAME}/ ${WEB_ROOT}/ \
--recursive || error_exit "Falha ao baixar arquivos do S3"

#########################################################
# VALIDA INDEX.HTML
#########################################################

if [ ! -f "${WEB_ROOT}/index.html" ]; then
    error_exit "index.html não encontrado"
fi

echo "index.html encontrado"

#########################################################
# COLETA METADADOS DA EC2 (IMDSv2)
#########################################################

echo "Coletando metadados da instância EC2..."

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60") \
    || error_exit "Falha ao obter token IMDSv2"

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id) \
    || error_exit "Falha ao obter instance-id"

INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-type) \
    || error_exit "Falha ao obter instance-type"

AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone) \
    || error_exit "Falha ao obter availability-zone"

PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "N/A")

PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4) \
    || error_exit "Falha ao obter private-ip"

REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/region) \
    || error_exit "Falha ao obter region"

echo "Instance ID  : $INSTANCE_ID"
echo "Instance Type: $INSTANCE_TYPE"
echo "AZ           : $AZ"
echo "Public IP    : $PUBLIC_IP"
echo "Private IP   : $PRIVATE_IP"
echo "Region       : $REGION"

#########################################################
# INJETA METADADOS NO INDEX.HTML
#########################################################

echo "Injetando metadados no index.html..."

sed -i "s|{{INSTANCE_ID}}|${INSTANCE_ID}|g"     ${WEB_ROOT}/index.html || error_exit "Falha ao injetar INSTANCE_ID"
sed -i "s|{{INSTANCE_TYPE}}|${INSTANCE_TYPE}|g" ${WEB_ROOT}/index.html || error_exit "Falha ao injetar INSTANCE_TYPE"
sed -i "s|{{AZ}}|${AZ}|g"                       ${WEB_ROOT}/index.html || error_exit "Falha ao injetar AZ"
sed -i "s|{{PUBLIC_IP}}|${PUBLIC_IP}|g"         ${WEB_ROOT}/index.html || error_exit "Falha ao injetar PUBLIC_IP"
sed -i "s|{{PRIVATE_IP}}|${PRIVATE_IP}|g"       ${WEB_ROOT}/index.html || error_exit "Falha ao injetar PRIVATE_IP"
sed -i "s|{{REGION}}|${REGION}|g"               ${WEB_ROOT}/index.html || error_exit "Falha ao injetar REGION"

echo "Metadados injetados com sucesso"

#########################################################
# AJUSTA PERMISSÕES
#########################################################

echo "Ajustando permissões..."

chown -R nginx:nginx ${WEB_ROOT} || error_exit "Falha ao ajustar owner"

chmod -R 755 ${WEB_ROOT} || error_exit "Falha ao ajustar permissões"

#########################################################
# INICIA NGINX
#########################################################

echo "Iniciando nginx..."

systemctl start nginx || error_exit "Falha ao iniciar nginx"

#########################################################
# STATUS NGINX
#########################################################

echo "Verificando status do nginx..."

systemctl status nginx --no-pager

#########################################################
# TESTE LOCAL
#########################################################

echo "Testando resposta HTTP local..."

curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost \
    || error_exit "Nginx não respondeu localmente"

#########################################################
# VALIDA METADADOS NO HTML FINAL
#########################################################

echo "Validando substituição dos metadados..."

if grep -q '{{INSTANCE_ID}}' ${WEB_ROOT}/index.html; then
    error_exit "Placeholder {{INSTANCE_ID}} não foi substituído"
fi

echo "Validação dos metadados OK"

#########################################################
# FINALIZAÇÃO
#########################################################

echo "=================================================="
echo "USER DATA FINALIZADO COM SUCESSO"
echo "INSTANCE ID : $INSTANCE_ID"
echo "AZ          : $AZ"
echo "HORARIO     : $(date)"
echo "=================================================="
```

---

## O que esse script faz — passo a passo

| Etapa | Comando | Finalidade |
|---|---|---|
| Atualiza sistema | `dnf update -y` | Garante pacotes atualizados |
| Instala dependências | `dnf install -y nginx aws-cli` | Instala o servidor web e a CLI da AWS |
| Habilita nginx | `systemctl enable nginx` | Nginx sobe automaticamente em reboots |
| Limpa diretório web | `rm -rf /usr/share/nginx/html/*` | Remove arquivos padrão do nginx |
| Baixa site do S3 | `aws s3 cp --recursive` | Copia todos os arquivos do bucket |
| Coleta metadados | `curl http://169.254.169.254/...` | Obtém dados da instância via IMDSv2 |
| Injeta metadados | `sed -i "s|{{PLACEHOLDER}}|valor|g"` | Substitui placeholders no HTML |
| Ajusta permissões | `chown` + `chmod` | Nginx precisa ler os arquivos |
| Inicia nginx | `systemctl start nginx` | Sobe o servidor web |
| Valida localmente | `curl http://localhost` | Confirma que o site está respondendo |

---

# ETAPA 5 — Criar Auto Scaling Group

```
EC2 → Auto Scaling Groups → Create Auto Scaling group
```

---

## Configurações Gerais

| Campo | Valor |
|---|---|
| Nome | asg-workshop-site |
| Launch template | lt-workshop-site |

---

## Rede

| Campo | Valor |
|---|---|
| VPC | VPC default |
| Availability Zones | Selecionar **3 subnets** em AZs diferentes |

> Usar múltiplas subnets é o que garante alta disponibilidade real. Se uma AZ cair, as outras continuam servindo.

---

## Load Balancer

> **Sobre o Target Group:** Você **não precisa criar o Target Group manualmente**. Ao escolher "Attach to a new load balancer" abaixo, o ASG cria automaticamente o ALB, o Target Group e já registra as instâncias nele. Tudo junto, em uma única etapa.

Selecionar:

```
Attach to a new load balancer
```

| Campo | Valor |
|---|---|
| Tipo | Application Load Balancer |
| Nome | alb-workshop-site |
| Scheme | Internet-facing |
| Porta do listener | 80 |
| Security Group do ALB | **alb-sg** |

**Target Group (criado automaticamente pelo ASG):**

| Campo | Valor |
|---|---|
| Nome sugerido | tg-workshop-site (o ASG preenche automaticamente) |
| Protocolo | HTTP |
| Porta | 80 |

Não precisa alterar nada aqui — só confirmar que está na porta 80.

---

> # ⚠️ ATENÇÃO — ERRO MAIS COMUM DO WORKSHOP
>
> ## Não troque os Security Groups do ALB e da EC2
>
> Este é o erro mais fácil de cometer e o mais difícil de diagnosticar.
> Já causou falha em execuções anteriores deste workshop.
>
> ### Como o erro acontece
>
> Na tela de criação do ASG, no campo **"Security groups for the load balancer"**,
> é fácil selecionar o `ec2-sg` por engano em vez do `alb-sg`.
> Os dois aparecem na lista e os nomes são parecidos visualmente.
>
> ### O que acontece quando você erra
>
> - O ALB fica com o `ec2-sg` associado
> - O `ec2-sg` só permite entrada vinda do `alb-sg`
> - O ALB não consegue receber tráfego da internet
> - As instâncias ficam **Unhealthy** com erro **"Request timed out"**
> - O nginx está rodando normalmente — o problema é invisível nos logs da EC2
>
> ### A regra que nunca pode ser esquecida
>
> ```
> alb-sg   → associado ao ALB   → permite HTTP 80 de 0.0.0.0/0 (internet)
> ec2-sg   → associado à EC2    → permite HTTP 80 somente do alb-sg
> ```
>
> ### Como verificar se está certo
>
> Após criar o ASG, antes de esperar as instâncias subirem:
>
> ```
> EC2 → Load Balancers → [seu ALB] → aba "Security"
> ```
>
> O SG listado deve ser o `alb-sg`. Se aparecer `ec2-sg`, corrija imediatamente:
>
> ```
> Editar → remover ec2-sg → adicionar alb-sg → salvar
> ```
>
> ### Como corrigir se já errou
>
> ```
> EC2 → Load Balancers → [seu ALB] → aba Security → Editar
> Remover: ec2-sg
> Adicionar: alb-sg
> Salvar
> ```
>
> Após corrigir, aguardar 1-2 minutos e verificar o Target Group.
> As instâncias devem passar para **Healthy** automaticamente.

---

## Health Check

| Campo | Valor |
|---|---|
| Health check type | ELB |
| Health check path | / |
| Healthy threshold | 2 |
| Unhealthy threshold | 3 |
| Timeout | 5 segundos |
| Interval | 30 segundos |
| Success codes | 200 |
| Health check grace period | **120 segundos** |

> **CRÍTICO:** O grace period de 120 segundos é necessário porque o UserData leva tempo para executar (atualização do sistema, download do S3, etc.). Se o grace period for muito curto, o ASG vai marcar a instância como unhealthy e terminá-la antes do site estar pronto.

---

## Capacidade

| Configuração | Valor |
|---|---|
| Desired capacity | 2 |
| Minimum capacity | 2 |
| Maximum capacity | 4 |

---

## Finalizar

Revisar e criar o ASG. O ASG vai automaticamente:

1. Criar 2 instâncias EC2
2. Criar o ALB e o Target Group
3. Registrar as instâncias no Target Group
4. Aguardar o health check passar

---

# ETAPA 6 — Validar Instâncias

```
EC2 → Instances
```

Aguardar até que todas as instâncias mostrem:

- **Instance State:** Running
- **Status Checks:** 2/2 checks passed

Tempo estimado: 3 a 5 minutos.

---

# ETAPA 7 — Validar Target Group

```
EC2 → Target Groups → [nome do target group criado pelo ASG]
```

Na aba **Targets**, verificar que todas as instâncias estão com status:

```
Healthy
```

Se alguma instância estiver `Unhealthy`, consultar a seção de troubleshooting no final deste guia.

---

# ETAPA 8 — Testar a Aplicação

```
EC2 → Load Balancers → [alb-workshop-site]
```

Copiar o **DNS name** do ALB (formato: `alb-workshop-site-XXXXXXXX.us-east-1.elb.amazonaws.com`).

Abrir no navegador.

---

## Demonstração do Load Balancing

Ao atualizar a página (F5 ou botão "Recarregar"):

- O **Instance ID** muda
- A **Availability Zone** muda
- O **IP privado** muda

Isso demonstra que o ALB está distribuindo as requisições entre as instâncias em diferentes AZs.

> Dica para a apresentação: abrir em dois navegadores lado a lado e recarregar alternadamente para mostrar as instâncias diferentes respondendo.

---

# Troubleshooting — Diagnóstico e Soluções

## Como acessar os logs do UserData

Se algo falhar, o primeiro passo é sempre verificar o log:

```bash
cat /var/log/user-data.log
```

Para acompanhar em tempo real durante a inicialização:

```bash
tail -f /var/log/user-data.log
```

---

## Comandos de diagnóstico rápido

```bash
# Status do nginx
systemctl status nginx

# Arquivos no diretório web
ls -la /usr/share/nginx/html

# Verificar se metadados foram injetados
grep 'ec2-instance-id' /usr/share/nginx/html/index.html

# Testar acesso ao S3
aws s3 ls s3://meu-site-workshop

# Testar resposta local do nginx
curl -I http://localhost

# Ver logs do nginx
cat /var/log/nginx/error.log
```

---

## Problema 1 — Instância Unhealthy no Target Group

**Sintoma:** Instância aparece como `Unhealthy` no Target Group.

**Causas e soluções:**

| Causa | Como verificar | Solução |
|---|---|---|
| UserData ainda executando | Verificar uptime da instância | Aguardar — pode levar até 5 min |
| Nginx não iniciou | `systemctl status nginx` | Ver logs: `journalctl -u nginx` |
| Security group errado | Verificar inbound rules do ec2-sg | Origem deve ser `alb-sg`, não `0.0.0.0/0` |
| Health check path errado | Verificar configuração do Target Group | Path deve ser `/`, success code `200` |
| Grace period insuficiente | Verificar configuração do ASG | Aumentar para 180 segundos |

---

## Problema 2 — Site exibe "Nenhuma instância conectada"

**Sintoma:** O site carrega, mas mostra a tela de "Nenhuma instância conectada".

**Causa:** Os placeholders `{{INSTANCE_ID}}`, `{{AZ}}`, etc. não foram substituídos no `index.html`.

**Como verificar:**

```bash
grep '{{INSTANCE_ID}}' /usr/share/nginx/html/index.html
```

Se retornar resultado, os placeholders ainda estão no arquivo.

**Soluções:**

| Causa | Solução |
|---|---|
| UserData não executou a etapa de injeção | Verificar log: `cat /var/log/user-data.log` |
| Falha ao coletar metadados via IMDSv2 | Verificar se a instância tem acesso ao IMDS (não deve ter `HttpTokens: required` sem suporte) |
| Script colado incorretamente no Launch Template | Recriar o Launch Template e colar o script novamente |

---

## Problema 3 — Falha ao baixar arquivos do S3

**Sintoma:** Log mostra `Falha ao baixar arquivos do S3`.

**Causas e soluções:**

| Causa | Como verificar | Solução |
|---|---|---|
| IAM Role não anexada | `curl http://169.254.169.254/latest/meta-data/iam/info` | Verificar se a role aparece; recriar Launch Template com a role |
| Nome do bucket errado | Verificar variável `BUCKET_NAME` no script | Deve ser exatamente `meu-site-workshop` |
| Arquivos em subpasta no bucket | `aws s3 ls s3://meu-site-workshop/` | Mover arquivos para a raiz do bucket |
| Sem acesso à internet | `curl -I https://s3.amazonaws.com` | Verificar se a subnet tem rota para internet (Internet Gateway) |
| Permissão insuficiente na Role | Testar manualmente: `aws s3 ls s3://meu-site-workshop` | Verificar se a policy `AmazonS3ReadOnlyAccess` está na role |

---

## Problema 4 — UserData não executa

**Sintoma:** Log `/var/log/user-data.log` não existe ou está vazio.

**Causas e soluções:**

| Causa | Solução |
|---|---|
| Script colado sem `#!/bin/bash` na primeira linha | Recriar Launch Template com o shebang correto |
| Script com encoding errado (Windows CRLF) | Colar o script diretamente no console, sem copiar de editor Windows |
| Versão do Launch Template desatualizada | Verificar se o ASG está usando a versão mais recente do Launch Template |

**Como verificar se o UserData foi recebido pela instância:**

```bash
curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" \
    http://169.254.169.254/latest/user-data | head -5
```

A saída deve começar com `#!/bin/bash`.

---

## Problema 5 — ALB retorna 502 Bad Gateway

**Sintoma:** Acessar o DNS do ALB retorna erro 502.

**Causas e soluções:**

| Causa | Solução |
|---|---|
| Todas as instâncias unhealthy | Verificar Target Group e resolver problema das instâncias |
| Nginx não está rodando | `systemctl start nginx` na instância |
| Security group da EC2 bloqueando o ALB | Verificar inbound rule do `ec2-sg` — origem deve ser `alb-sg` |
| Target Group com porta errada | Verificar se o Target Group está configurado na porta 80 |

---

## Problema 6 — Instâncias sendo terminadas logo após criação

**Sintoma:** ASG cria instâncias mas elas são terminadas rapidamente.

**Causa:** Health check falhando antes do UserData terminar.

**Solução:** Aumentar o **Health Check Grace Period** no ASG para 180 segundos.

```
EC2 → Auto Scaling Groups → [asg-workshop-site] → Edit → Health check grace period → 180
```

---

# Serviços AWS Demonstrados

| Serviço | Função no Workshop |
|---|---|
| S3 | Armazena os arquivos do site de forma centralizada |
| IAM Role | Permite que a EC2 acesse o S3 sem usar access keys |
| EC2 | Executa o nginx e serve o site |
| Auto Scaling Group | Mantém o número desejado de instâncias e substitui instâncias com falha |
| Application Load Balancer | Distribui o tráfego entre as instâncias em múltiplas AZs |
| Security Groups | Controla o fluxo de rede entre ALB e EC2 |
| IMDSv2 | Fornece metadados da instância de forma segura para o UserData |

---

# Frases para Explicar no Workshop

**Sobre IAM Role:**
> "A EC2 assume uma IAM Role para acessar o bucket sem utilizar access keys. As credenciais são temporárias e rotacionadas automaticamente pela AWS."

**Sobre ALB:**
> "O Load Balancer distribui as requisições entre múltiplas instâncias. O visitante sempre acessa o mesmo DNS, mas cai em instâncias diferentes."

**Sobre ASG:**
> "O Auto Scaling Group garante alta disponibilidade. Se uma instância falhar, o ASG cria uma nova automaticamente, sem intervenção manual."

**Sobre UserData:**
> "O bootstrap da aplicação acontece automaticamente na inicialização da instância. Não precisamos de acesso SSH ou configuração manual."

**Sobre S3:**
> "O S3 centraliza os artefatos da aplicação. Todas as instâncias baixam do mesmo bucket, garantindo consistência."

**Sobre IMDSv2:**
> "O Instance Metadata Service permite que a instância conheça seus próprios dados — instance ID, AZ, IPs — sem precisar de nenhuma configuração externa."

---

# Resultado Final

Ao concluir o workshop, você terá:

- Aplicação web publicada automaticamente
- Alta disponibilidade com múltiplas AZs
- Load balancing distribuindo o tráfego
- EC2s provisionadas e configuradas sem intervenção manual
- Deploy automático via UserData
- Arquitetura AWS demonstrável e funcional

Sem nenhum acesso manual ao Linux.

---

# Checklist Pré-Workshop

Use esta lista antes de apresentar para garantir que tudo funciona:

- [ ] Bucket S3 `meu-site-workshop` criado e com os arquivos na raiz
- [ ] IAM Role `EC2-S3-Role` criada com `AmazonS3ReadOnlyAccess`
- [ ] Security Group `alb-sg` com inbound HTTP 80 de `0.0.0.0/0`
- [ ] Security Group `ec2-sg` com inbound HTTP 80 somente do `alb-sg`
- [ ] Launch Template `lt-workshop-site` com AMI Amazon Linux 2023, `ec2-sg` e `EC2-S3-Role`
- [ ] UserData colado corretamente no Launch Template (começando com `#!/bin/bash`)
- [ ] ASG `asg-workshop-site` criado com 2 instâncias desired, 3 subnets, grace period 120s
- [ ] ALB e Target Group criados automaticamente pelo ASG (não criar manualmente)
- [ ] Todas as instâncias `Running` com `2/2 checks passed`
- [ ] Target Group com todas as instâncias `Healthy`
- [ ] DNS do ALB abre o site no navegador
- [ ] Refresh mostra instâncias diferentes (instance-id e AZ mudam)
