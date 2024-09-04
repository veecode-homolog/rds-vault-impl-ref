
resource "vault_mount" "kvv2" {
  path        = "root_db"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine mount"
}

resource "vault_kv_secret_v2" "kvv2" {
  mount                      = vault_mount.kvv2.path
  name                       = "secret"
  cas                        = 1
  delete_all_versions        = true
  data_json                  = jsonencode(
  {
    master       = "${local.config.password}"
  }
  )

}

resource "vault_mount" "db" {
  path = "postgres"
  type = "database"
}

resource "vault_database_secrets_mount" "db" {
  path = "datasources"

  postgresql {
    name              = "postgres"
    username          = aws_db_instance.RDS_VKPR.username
    password          = local.config.password
    connection_url    = "postgresql://{{username}}:{{password}}@${aws_db_instance.RDS_VKPR.address}:${aws_db_instance.RDS_VKPR.port}/postgres"
    verify_connection = true
    allowed_roles = [
      "dev2","readWrite","readOnly"
    ]
  }
  depends_on = [ aws_db_instance.RDS_VKPR, null_resource.check_database_state]
}

resource "vault_database_secret_backend_role" "readOnly" {
  name    = "readOnly"
  backend = vault_database_secrets_mount.db.path
  db_name = vault_database_secrets_mount.db.postgresql[0].name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
  ]
}

resource "vault_database_secret_backend_role" "readWrite" {
  name    = "readWrite"
  backend = vault_database_secrets_mount.db.path
  db_name = vault_database_secrets_mount.db.postgresql[0].name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT ALL ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
  ]
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