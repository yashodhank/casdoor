#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status.

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Validate necessary variables and formats
validate_env() {
    log "Validating environment variables..."
    local mandatory_vars=("CASDOOR_HTTPPORT" "CASDOOR_DRIVERNAME")
    for var in "${mandatory_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log "Error: Environment variable $var is not set."
            exit 1
        fi
    done

    # Example: Validate HTTPPORT is a number
    if ! [[ "${CASDOOR_HTTPPORT}" =~ ^[0-9]+$ ]]; then
        log "Error: CASDOOR_HTTPPORT must be a number."
        exit 1
    fi
}

# Function to construct dataSourceName based on the driver
construct_dataSourceName() {
    # Retrieve database user and password from Docker secrets or default to environment variables if secrets are not found
    local db_user=$(get_docker_secret "casdoor_db_user" "${CASDOOR_DBUSER:-casdoor}")
    local db_password=$(get_docker_secret "casdoor_db_password" "${CASDOOR_DBPASSWORD}")

    # Set default values for host, port, name, and driver if not provided in environment variables
    local db_host="${CASDOOR_DBHOST:-localhost}"
    local db_port="${CASDOOR_DBPORT:-3306}"
    local db_name="${CASDOOR_DBNAME:-casdoor}"
    local db_driver="${CASDOOR_DRIVERNAME:-mysql}"

    # Determine the connection string based on the database driver
    case $db_driver in
        # For MySQL and MariaDB
        mysql | mariadb)
            # Standard MySQL/MariaDB connection string format
            echo "${db_user}:${db_password}@tcp(${db_host}:${db_port})/${db_name}"
            ;;

        # For PostgreSQL and CockroachDB
        postgres | cockroachdb)
            # Additional parameters for PostgreSQL and CockroachDB, defaults for PostgreSQL
            local extra_params="?sslmode=disable"

            # Additional parameter for CockroachDB for handling serialization
            if [[ "$db_driver" == "cockroachdb" ]]; then
                extra_params="?sslmode=disable&serial_normalization=virtual_sequence"
            fi

            # Standard PostgreSQL connection string format with additional parameters as needed
            echo "user=${db_user} password=${db_password} host=${db_host} port=${db_port} dbname=${db_name}${extra_params}"
            ;;

        # For SQLite
        sqlite)
            # SQLite uses a simple file path with optional parameters
            echo "file:${db_name}.db?cache=shared"
            ;;

        # Default case for unsupported database drivers
        *)
            log "Unsupported database driver: ${db_driver}"
            exit 1
            ;;
    esac
}

# Validate and construct logConfig
construct_logConfig() {
    local filename="${CASDOOR_LOGFILENAME:-logs/casdoor.log}"
    local maxdays="${CASDOOR_LOGMAXDAYS:-99999}"
    local perm="${CASDOOR_LOGPERM:-0770}"

    echo '{"filename": "'$filename'", "maxdays":'$maxdays', "perm":"'$perm'"}'
}

# Validate and construct quota
construct_quota() {
    local organization="${CASDOOR_QUOTA_ORGANIZATION:-1}"
    local user="${CASDOOR_QUOTA_USER:-1}"
    local application="${CASDOOR_QUOTA_APPLICATION:-1}"
    local provider="${CASDOOR_QUOTA_PROVIDER:-1}"

    echo '{"organization": '$organization', "user": '$user', "application": '$application', "provider": '$provider'}'
}

# Generate configuration file
generate_config() {
    log "Generating configuration file..."
    local dataSourceName=$(construct_dataSourceName)
    local logConfig=$(construct_logConfig)
    local quota=$(construct_quota)

    cat << EOF > /web/conf/app.conf
appname = ${CASDOOR_APPNAME:-casdoor}
httpport = ${CASDOOR_HTTPPORT:-8000}
runmode = ${CASDOOR_RUNMODE:-dev}
copyrequestbody = ${CASDOOR_COPYREQUESTBODY:-true}
driverName = ${CASDOOR_DRIVERNAME:-mysql}
dataSourceName = $dataSourceName
dbName = ${CASDOOR_DBNAME:-casdoor}
tableNamePrefix = ${CASDOOR_TABLENAMEPREFIX}
showSql = ${CASDOOR_SHOWSQL:-false}
redisEndpoint = ${CASDOOR_REDISENDPOINT}
defaultStorageProvider = ${CASDOOR_DEFAULTSTORAGEPROVIDER}
isCloudIntranet = ${CASDOOR_ISCLOUDINTRANET:-false}
authState = "${CASDOOR_AUTHSTATE:-casdoor}"
socks5Proxy = "${CASDOOR_SOCKS5PROXY:-127.0.0.1:10808}"
verificationCodeTimeout = ${CASDOOR_VERIFICATIONCODETIMEOUT:-10}
initScore = ${CASDOOR_INITSCORE:-0}
logPostOnly = ${CASDOOR_LOGPOSTONLY:-true}
isUsernameLowered = ${CASDOOR_ISUSERNAMELOWERED:-false}
origin = ${CASDOOR_ORIGIN}
originFrontend = ${CASDOOR_ORIGINFRONTEND}
staticBaseUrl = "${CASDOOR_STATICBASEURL:-https://cdn.casbin.org}"
isDemoMode = ${CASDOOR_ISDEMOMODE:-false}
batchSize = ${CASDOOR_BATCHSIZE:-100}
enableGzip = ${CASDOOR_ENABLEGZIP:-true}
ldapServerPort = ${CASDOOR_LDAPSERVERPORT:-389}
radiusServerPort = ${CASDOOR_RADIUSSERVERPORT:-1812}
radiusSecret = "${CASDOOR_RADIUSSECRET:-secret}"
quota = $quota
logConfig = $logConfig
initDataFile = "${CASDOOR_INITDATAFILE:-./init_data.json}"
frontendBaseDir = "${CASDOOR_FRONTENDBASEDIR:-../casdoor}"
EOF
    log "Configuration file generated."
}

# Main execution
main() {
    log "Starting the entrypoint script..."
    validate_env
    generate_config
    log "Starting the server..."
    exec "/server"
}

main
