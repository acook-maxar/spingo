
if [ ! -d /${USER}/.hal ]; then
  mkdir /${USER}/.hal
fi

hal config --set-current-deployment ${DEPLOYMENT_NAME}

if [ ${DEPLOYMENT_INDEX} -eq 0 ]; then
  # remove default deployment that gets automatically created
  yq d -i ~/.hal/config 'deploymentConfigurations[0]'
fi

GCS_SA_DEST="${ACCOUNT_PATH}"

hal config storage gcs edit \
    --project $(gcloud info --format='value(config.project)') \
    --json-path "$GCS_SA_DEST" \
    --deployment ${DEPLOYMENT_NAME}
hal config storage edit --type gcs \
    --deployment ${DEPLOYMENT_NAME}

hal config provider docker-registry enable \
    --deployment ${DEPLOYMENT_NAME}

hal config provider docker-registry account add "${DOCKER}" \
    --address gcr.io \
    --password-file "$GCS_SA_DEST" \
    --username _json_key \
    --deployment ${DEPLOYMENT_NAME}
    

hal config provider kubernetes enable \
    --deployment ${DEPLOYMENT_NAME}

hal config provider kubernetes account add ${ACCOUNT_NAME} \
    --docker-registries "${DOCKER}" \
    --provider-version v2 \
    --only-spinnaker-managed=true \
    --kubeconfig-file ${KUBE_CONFIG} \
    --deployment ${DEPLOYMENT_NAME}

hal config provider kubernetes account edit ${ACCOUNT_NAME} \
    --add-read-permission "${ADMIN_GROUP}" \
    --add-write-permission "${ADMIN_GROUP}" \
    --deployment ${DEPLOYMENT_NAME}

hal config version edit --version $(hal version list -q -o json | jq -r '.latestSpinnaker') \
    --deployment ${DEPLOYMENT_NAME}

hal config deploy edit --type distributed --account-name "${ACCOUNT_NAME}" \
    --deployment ${DEPLOYMENT_NAME}

hal config edit --timezone America/New_York \
    --deployment ${DEPLOYMENT_NAME}

hal config generate \
    --deployment ${DEPLOYMENT_NAME}

# set-up admin groups for fiat:
tee /${USER}/.hal/${DEPLOYMENT_NAME}/profiles/fiat-local.yml << FIAT_LOCAL
fiat:
  admin:
    roles:
      - ${ADMIN_GROUP}
FIAT_LOCAL

# set-up redis (memorystore):
tee /${USER}/.hal/${DEPLOYMENT_NAME}/profiles/gate-local.yml << GATE_LOCAL
redis:
  configuration:
    secure: true
GATE_LOCAL

tee /${USER}/.hal/${DEPLOYMENT_NAME}/service-settings/redis.yml << REDIS
overrideBaseUrl: redis://${SPIN_REDIS_ADDR}
skipLifeCycleManagement: true
REDIS

${SPIN_SERVICES}

# set-up orca to use cloudsql proxy
tee /tmp/halconfig-orca-patch-${DEPLOYMENT_INDEX}.yml << ORCA_PATCH
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.name: cloudsql-proxy
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.port: 3306
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.dockerImage: "gcr.io/cloudsql-docker/gce-proxy:1.13"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.command.0: "'/cloud_sql_proxy'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.command.1: "'--dir=/cloudsql'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.command.2: "'-instances=${DB_CONNECTION_NAME}=tcp:3306'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.command.3: "'-credential_file=/secrets/cloudsql/secret'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.mountPath: /cloudsql
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.secretVolumeMounts.0.mountPath: /secrets/cloudsql
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-orca.0.secretVolumeMounts.0.secretName: cloudsql-instance-credentials
ORCA_PATCH

yq write -i -s /tmp/halconfig-orca-patch-${DEPLOYMENT_INDEX}.yml /${USER}/.hal/config && rm /tmp/halconfig-orca-patch-${DEPLOYMENT_INDEX}.yml

# set-up clouddriver to use cloudsql proxy
tee /tmp/halconfig-clouddriver-patch-${DEPLOYMENT_INDEX}.yml << CLOUDDRIVER_PATCH
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.name: cloudsql-proxy
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.port: 3306
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.dockerImage: "gcr.io/cloudsql-docker/gce-proxy:1.13"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.command.0: "'/cloud_sql_proxy'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.command.1: "'--dir=/cloudsql'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.command.2: "'-instances=${DB_CONNECTION_NAME}=tcp:3306'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.command.3: "'-credential_file=/secrets/cloudsql/secret'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.mountPath: /cloudsql
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.secretVolumeMounts.0.mountPath: /secrets/cloudsql
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.0.secretVolumeMounts.0.secretName: cloudsql-instance-credentials
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.1.name: token-refresh
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.1.dockerImage: justinrlee/gcloud-auth-helper:stable
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-clouddriver.1.mountPath: /tmp/gcloud
CLOUDDRIVER_PATCH

yq write -i -s /tmp/halconfig-clouddriver-patch-${DEPLOYMENT_INDEX}.yml /${USER}/.hal/config && rm /tmp/halconfig-clouddriver-patch-${DEPLOYMENT_INDEX}.yml


tee /${USER}/.hal/${DEPLOYMENT_NAME}/service-settings/clouddriver.yml << EOF
kubernetes:
  serviceAccountName: spinnaker-onboarding

EOF

# set-up front50 to use cloudsql proxy
tee /tmp/halconfig-front50-patch-${DEPLOYMENT_INDEX}.yml << FRONT50_PATCH
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.name: cloudsql-proxy
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.port: 3306
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.dockerImage: "gcr.io/cloudsql-docker/gce-proxy:1.13"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.command.0: "'/cloud_sql_proxy'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.command.1: "'--dir=/cloudsql'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.command.2: "'-instances=${DB_CONNECTION_NAME}=tcp:3306'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.command.3: "'-credential_file=/secrets/cloudsql/secret'"
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.mountPath: /cloudsql
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.secretVolumeMounts.0.mountPath: /secrets/cloudsql
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.sidecars.spin-front50.0.secretVolumeMounts.0.secretName: cloudsql-instance-credentials
FRONT50_PATCH

yq write -i -s /tmp/halconfig-front50-patch-${DEPLOYMENT_INDEX}.yml /${USER}/.hal/config && rm /tmp/halconfig-front50-patch-${DEPLOYMENT_INDEX}.yml

# set-up replica patch
tee /tmp/halconfig-replica-patch-${DEPLOYMENT_INDEX}.yml << REPLICA_PATCH
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-front50.replicas: 2
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-front50.limits.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-front50.requests.cpu: 15m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-front50.requests.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-clouddriver.replicas: 2
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-clouddriver.limits.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-clouddriver.requests.cpu: 15m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-clouddriver.requests.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-deck.replicas: 2
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-gate.replicas: 2
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-gate.limits.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-gate.requests.cpu: 15m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-gate.requests.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-rosco.replicas: 2
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-rosco.limits.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-rosco.requests.cpu: 15m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-rosco.requests.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-fiat.replicas: 2
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-fiat.limits.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-fiat.requests.cpu: 15m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-fiat.requests.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-orca.replicas: 2
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-orca.limits.memory: 125Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-orca.requests.cpu: 15m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.spin-orca.requests.memory: 125Mi
REPLICA_PATCH

yq write -i -s /tmp/halconfig-replica-patch-${DEPLOYMENT_INDEX}.yml /${USER}/.hal/config && rm /tmp/halconfig-replica-patch-${DEPLOYMENT_INDEX}.yml

# set-up resources patch
tee /tmp/halconfig-resources-patch-${DEPLOYMENT_INDEX}.yml << RESOURCES_PATCH
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.clouddriver.limits.memory: 10Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.clouddriver.requests.cpu: 500m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.clouddriver.requests.memory: 5Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.deck.limits.memory: 500Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.deck.requests.cpu: 25m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.deck.requests.memory: 250Mi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.echo.limits.memory: 2Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.echo.requests.cpu: 100m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.echo.requests.memory: 1Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.fiat.limits.memory: 2Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.fiat.requests.cpu: 100m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.fiat.requests.memory: 1Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.front50.limits.memory: 2Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.front50.requests.cpu: 100m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.front50.requests.memory: 1Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.gate.limits.memory: 2Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.gate.requests.cpu: 100m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.gate.requests.memory: 1Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.igor.limits.memory: 2Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.igor.requests.cpu: 100m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.igor.requests.memory: 1Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.orca.limits.memory: 4Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.orca.requests.cpu: 250m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.orca.requests.memory: 2Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.rosco.limits.memory: 2Gi
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.rosco.requests.cpu: 100m
deploymentConfigurations.${DEPLOYMENT_INDEX}.deploymentEnvironment.customSizing.rosco.requests.memory: 1Gi
RESOURCES_PATCH

yq write -i -s /tmp/halconfig-resources-patch-${DEPLOYMENT_INDEX}.yml /${USER}/.hal/config && rm /tmp/halconfig-resources-patch-${DEPLOYMENT_INDEX}.yml

tee /${USER}/.hal/${DEPLOYMENT_NAME}/profiles/orca-local.yml << ORCA_LOCAL
sql:
  enabled: true
  connectionPool:
    jdbcUrl: jdbc:mysql://localhost:3306/orca?useSSL=false&useUnicode=true&characterEncoding=utf8
    user: orca_service
    password: ${DB_SERVICE_USER_PASSWORD}
    connectionTimeout: 5000
    maxLifetime: 30000
    # MariaDB-specific:
    maxPoolSize: 50
  migration:
    jdbcUrl: jdbc:mysql://localhost:3306/orca?useSSL=false&useUnicode=true&characterEncoding=utf8
    user: orca_migrate
    password: ${DB_MIGRATE_USER_PASSWORD}

# Ensure we're only using SQL for accessing execution state
executionRepository:
  sql:
    enabled: true
  redis:
    enabled: false

# Reporting on active execution metrics will be handled by SQL
monitor:
  activeExecutions:
    redis: false
ORCA_LOCAL

tee /${USER}/.hal/${DEPLOYMENT_NAME}/profiles/clouddriver-local.yml << CLOUDDRIVER_LOCAL
sql:
  enabled: true
  taskRepository:
    enabled: true
  cache:
    enabled: true
    # These parameters were determined to be optimal via benchmark comparisons
    # in the Netflix production environment with Aurora. Setting these too low
    # or high may negatively impact performance. These values may be sub-optimal
    # in some environments.
    readBatchSize: 500
    writeBatchSize: 300
  scheduler:
    enabled: false
  connectionPools:
    default:
      # additional connection pool parameters are available here,
      # for more detail and to view defaults, see:
      # https://github.com/spinnaker/kork/blob/master/kork-sql/src/main/kotlin/com/netflix/spinnaker/kork/sql/config/ConnectionPoolProperties.kt
      default: true
      jdbcUrl: jdbc:mysql://localhost:3306/clouddriver?useSSL=false&useUnicode=true&characterEncoding=utf8
      user: clouddriver_service
      password: ${DB_CLOUDDRIVER_SVC_PASSWORD}
      # password: depending on db auth and how spinnaker secrets are managed
    # The following tasks connection pool is optional. At Netflix, clouddriver
    # instances pointed to Aurora read replicas have a tasks pool pointed at the
    # master. Instances where the default pool is pointed to the master omit a
    # separate tasks pool.
    tasks:
      user: clouddriver_service
      password: ${DB_CLOUDDRIVER_SVC_PASSWORD}
      jdbcUrl: jdbc:mysql://localhost:3306/clouddriver?useSSL=false&useUnicode=true&characterEncoding=utf8
  migration:
    user: clouddriver_migrate
    password: ${DB_CLOUDDRIVER_MIGRATE_PASSWORD}
    jdbcUrl: jdbc:mysql://localhost:3306/clouddriver?useSSL=false&useUnicode=true&characterEncoding=utf8

redis:
  enabled: true
  connection: redis://${SPIN_REDIS_ADDR}
  cache:
    enabled: false
  scheduler:
    enabled: true
  taskRepository:
    enabled: false
CLOUDDRIVER_LOCAL

tee /${USER}/.hal/${DEPLOYMENT_NAME}/profiles/front50-local.yml << FRONT50_LOCAL
sql:
  enabled: true
  connectionPools:
    default:
     # additional connection pool parameters are available here,
     # for more detail and to view defaults, see:
     # https://github.com/spinnaker/kork/blob/master/kork-sql/src/main/kotlin/com/netflix/spinnaker/kork/sql/config/ConnectionPoolProperties.kt 
      default: true
      jdbcUrl: jdbc:mysql://localhost:3306/front50?useSSL=false&useUnicode=true&characterEncoding=utf8
      user: front50_service
      password: ${DB_FRONT50_SVC_PASSWORD}
  migration:
    user: front50_migrate
    password: ${DB_FRONT50_MIGRATE_PASSWORD}
    jdbcUrl: jdbc:mysql://localhost:3306/front50?useSSL=false&useUnicode=true&characterEncoding=utf8

spinnaker:
  gcs:
    enabled: false

redis:
  enabled: true
  connection: redis://${SPIN_REDIS_ADDR}
  cache:
    enabled: false
  scheduler:
    enabled: true
  taskRepository:
    enabled: false
FRONT50_LOCAL

# Changing health check to be native instead of wget https://github.com/spinnaker/spinnaker/issues/4479
tee /${USER}/.hal/${DEPLOYMENT_NAME}/service-settings/gate.yml << EOF
kubernetes:
  useExecHealthCheck: false

EOF

if [[ -f /${USER}/vault/dyn_acct_${DEPLOYMENT_NAME}_rw_token && -s /${USER}/vault/dyn_acct_${DEPLOYMENT_NAME}_rw_token && -f /${USER}/vault/dyn_acct_${DEPLOYMENT_NAME}_ro_token && -s /${USER}/vault/dyn_acct_${DEPLOYMENT_NAME}_ro_token ]]; then
    
    echo "Dynamic Account Tokens found so configuring dynamic account for deployment ${DEPLOYMENT_NAME}"

    cp /${USER}/vault/dyn_acct_${DEPLOYMENT_NAME}_rw_token /home/${USER}/.vault-token

    if [ ! -f tee /${USER}/.kube/kubeconfig_patch.yml ]; then
        tee /${USER}/.kube/kubeconfig_patch.yml << EOF
users.0.user.exec.apiVersion: client.authentication.k8s.io/v1beta1
users.0.user.exec.args[+]: "/tmp/gcloud/auth_token"
users.0.user.exec.command: /bin/cat
EOF
    fi
    

    echo "Setting Dynamic Account Secret for deployment ${DEPLOYMENT_NAME}"
    # First we read the existing account information, then we lookup the contents of the kubeconfigFile
    # and append it as a kubeconfigContents element, lastly we append that to the kubernetes.account list
    # and store that into the vault secret
    yq r -j \
        /${USER}/.hal/config deploymentConfigurations.${DEPLOYMENT_INDEX}.providers.kubernetes.accounts.0 | \
        jq --arg contents "$(yq r $(yq r /${USER}/.hal/config deploymentConfigurations.${DEPLOYMENT_INDEX}.providers.kubernetes.accounts.0.kubeconfigFile) | \
         yq d - users.0.user.token | yq w - -s /${USER}/.kube/kubeconfig_patch.yml | sed -E ':a;N;$!ba;s/\r{0,1}\n/\n/g')" \
        'del(.kubeconfigFile) | . += {"kubeconfigContents":$contents} | {"kubernetes":{"accounts":[.]}}' | \
        vault kv put \
        -address="https://${VAULT_ADDR}" \
        secret/dynamic_accounts/spinnaker -
    
    echo "Configuring Spinnaker dynamic account for deployment ${DEPLOYMENT_NAME}"

    tee /${USER}/.hal/${DEPLOYMENT_NAME}/profiles/spinnakerconfig.yml << DYN_CONFIG
spring:
  profiles:
    include: vault
  cloud:
    config:
      server:
        vault:
          host: ${VAULT_ADDR}
          port: 443
          scheme: https
          backend: secret/dynamic_accounts
          kvVersion: 1
          default-key: spinnaker
          token: $(cat /${USER}/vault/dyn_acct_${DEPLOYMENT_NAME}_ro_token)

DYN_CONFIG

    rm /home/${USER}/.vault-token
else
    echo "Dynamic Account Tokens NOT found so skipping configuring dynamic account for deployment ${DEPLOYMENT_NAME}"
fi
tee /${USER}/.hal/${DEPLOYMENT_NAME}/profiles/settings-local.js << SETTINGS_LOCAL
window.spinnakerSettings.notifications.email.enabled = false;
window.spinnakerSettings.notifications.bearychat.enabled = false;
SETTINGS_LOCAL

echo "Running initial Spinnaker deployment for deployment named ${DEPLOYMENT_NAME}"
hal deploy apply \
    --deployment ${DEPLOYMENT_NAME}
