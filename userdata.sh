#!/bin/bash

#########################################################
# CONFIGURAÇÕES
#########################################################
# Subtitua "BUCKET_NAME" pelo nome do bucket criado

BUCKET_NAME="workshop-usergroupsr"
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

# Obtém token IMDSv2 (válido por 60 segundos)
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

sed -i "s|{{INSTANCE_ID}}|${INSTANCE_ID}|g"   ${WEB_ROOT}/index.html || error_exit "Falha ao injetar INSTANCE_ID"
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
