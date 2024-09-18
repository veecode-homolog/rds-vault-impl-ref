resource "aws_security_group" "rds_sg" {
  name        = "${local.config.identifier}-security-group"
  description = "Security group for RDS instance"
  vpc_id      = "${local.config.vpc_id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-security-group"
  }
}
resource "aws_db_subnet_group" "my_db_subnet_group" {
  name       = "${local.config.identifier}-subnet-group"
  subnet_ids = local.config.subnet_ids
  tags = {
    Name = "${local.config.identifier}-subnets"
  }
}

resource "aws_db_instance" "RDS_VKPR" {
    identifier             = local.config.identifier
    instance_class         = local.config.instance_class
    allocated_storage      = local.config.allocated_storage
    engine                 = local.config.engine
    engine_version         = local.config.engine_version
    db_name  = local.config.instance_name
    username = local.config.username
    password = local.config.password
    skip_final_snapshot = true
    publicly_accessible = true
    vpc_security_group_ids = [aws_security_group.rds_sg.id]
    db_subnet_group_name   = aws_db_subnet_group.my_db_subnet_group.name     
    tags = {
    name = "VKPR-RDS"
  }
}

resource "null_resource" "check_database_state" {
  depends_on = [ aws_db_instance.RDS_VKPR ]
  provisioner "local-exec" {

    command = <<EOF
#!/bin/bash

# Variáveis de conexão com o banco de dados
DB_HOST="${aws_db_instance.RDS_VKPR.address}"
DB_USER="${aws_db_instance.RDS_VKPR.username}"
DB_PASS="${local.config.password}"
DB_NAME="postgres"

# Número máximo de tentativas
MAX_ATTEMPTS=30

# Contador de tentativas
attempts=0

echo "Testando conexão com o banco de dados..."

# Loop while para tentar a conexão até atingir o número máximo de tentativas
while [ $attempts -lt $MAX_ATTEMPTS ]; do
    # Tentativa de conexão com o banco de dados
    PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" -p 5432 -c "SELECT 1;" >/dev/null 2>&1

    # Verifica o código de saída do comando anterior (0 para sucesso, diferente de zero para falha)
    if [ $? -eq 0 ]; then
        echo "Conexão bem-sucedida!"
        exit 0  # Conexão bem-sucedida, sair com status de sucesso
    else
        echo "Tentativa $((attempts+1)) falhou. Tentando novamente..."
        attempts=$((attempts+1))
        sleep 10  # Espera 10 segundos antes de tentar novamente
    fi
done

# Se chegou até aqui, todas as tentativas falharam
echo "Não foi possível conectar ao banco de dados após $MAX_ATTEMPTS tentativas."
exit 1  # Sair com status de falha
    EOF
  }
}

resource "null_resource" "create_connection_vault" {
  depends_on = [ null_resource.check_database_state ]
  provisioner "local-exec" {

    command = <<EOF
!/bin/bash

# Variáveis de conexão com o banco de dados e com o Vault

DB_IDENTIFIER="${local.config.identifier}"
DB_HOST="${aws_db_instance.RDS_VKPR.address}"
DB_USER="${aws_db_instance.RDS_VKPR.username}"
DB_PASS="${local.config.password}"
DB_NAME="postgres"
VAULT_ADDR="${local.config.vault_address}"
VAULT_TOKEN="${local.config.vault_token}"
VAULT_DATABASE_ENGINE="${local.config.vault_database_engine}"

# Cria a conexão com o banco de dados no Vault
if curl --header "X-Vault-Token: $VAULT_TOKEN" \
   --request POST \
   --data "{
      \"plugin_name\": \"postgresql-database-plugin\",
      \"allowed_roles\": [\"$DB_IDENTIFIER-readOnly\", \"$DB_IDENTIFIER-readWrite\"],
      \"connection_url\": \"postgresql://{{username}}:{{password}}@$DB_HOST:5432/postgres\",
      \"username\": \"$DB_USER\",
      \"password\": \"$DB_PASS\"
      }" \
   $VAULT_ADDR/v1/$VAULT_DATABASE_ENGINE/config/$DB_IDENTIFIER; then
    echo "Conexão com o banco de dados criada com sucesso!"
else
    echo "Erro ao criar a conexão com o banco de dados."
    exit 1
fi

# Cria as roles de conexão no Vault
if curl --header "X-Vault-Token: $VAULT_TOKEN" \
   --request POST \
   --data "{
      \"db_name\": \"$DB_IDENTIFIER\",
      \"creation_statements\": \"CREATE ROLE \\\"{{name}}\\\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';GRANT SELECT ON ALL TABLES IN SCHEMA public TO \\\"{{name}}\\\";\"
      }" \
   $VAULT_ADDR/v1/$VAULT_DATABASE_ENGINE/roles/$DB_IDENTIFIER-readOnly; then
    echo "Role de conexão somente leitura criada com sucesso!"
else
    echo "Erro ao criar a role de conexão somente leitura."
    exit 1
fi

if curl --header "X-Vault-Token: $VAULT_TOKEN" \
   --request POST \
   --data "{
      \"db_name\": \"$DB_IDENTIFIER\",
      \"creation_statements\": \"CREATE ROLE \\\"{{name}}\\\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';GRANT ALL ON ALL TABLES IN SCHEMA public TO \\\"{{name}}\\\";\"
      }" \
   $VAULT_ADDR/v1/$VAULT_DATABASE_ENGINE/roles/$DB_IDENTIFIER-readWrite; then
    echo "Role de conexão com permissão de escrita criada com sucesso!"
else
    echo "Erro ao criar a role de conexão com permissão de escrita."
    exit 1
fi

if curl --header "X-Vault-Token: $VAULT_TOKEN" \
   --request POST \
   --data "{
      \"db_name\": \"$DB_IDENTIFIER\",
      \"creation_statements\": \"CREATE ROLE \\\"{{name}}\\\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' CREATEDB;GRANT postgres TO \\\"{{name}}\\\";\"
      }" \
   $VAULT_ADDR/v1/$VAULT_DATABASE_ENGINE/roles/$DB_IDENTIFIER-vaultActions; then
    echo "Role para o githubActions criada com sucesso!"
else
    echo "Erro ao criar a role para o githubActions."
    exit 1
fi


# Cria o secret de usuário, host e password do banco de dados no Vault
if curl --header "X-Vault-Token: $VAULT_TOKEN" \
   --request POST \
   --data "{ 
        \"data\": {
              \"username\": \"$DB_USER\",
              \"password\": \"$DB_PASS\",
              \"host\": \"$DB_HOST\"
        }
      }" \
   $VAULT_ADDR/v1/secrets/data/environment-vault-impl-ref/databases/$DB_IDENTIFIER; then
    echo "Secret de usuário, host e password do banco de dados criado com sucesso!"
else
    echo "Erro ao criar o secret de usuário, host e password do banco de dados."
    exit 1
fi    
    EOF
  }
}
