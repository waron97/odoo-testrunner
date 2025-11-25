#!/bin/bash
set -e

# Function to wait for database to be ready (OCA style)
wait_for_db() {
    echo "Waiting for database to be ready..."
    while ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"; do
        echo "Database is not ready yet. Waiting..."
        sleep 2
    done
    echo "Database is ready!"
}

# OCA style wait function (alias)
oca_wait_for_postgres() {
    wait_for_db
}

# Function to check if database exists
check_database_exists() {
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME" 2>/dev/null
}

remove_from_csv() {
    local list="$1"
    local item="$2"
    local IFS=','
    read -ra entries <<< "$list"

    local filtered=()
    for entry in "${entries[@]}"; do
        [[ -z "$entry" ]] && continue
        if [[ "$entry" != "$item" ]]; then
            filtered+=("$entry")
        fi
    done

    local result=""
    for entry in "${filtered[@]}"; do
        if [[ -z "$result" ]]; then
            result="$entry"
        else
            result="$result,$entry"
        fi
    done

    echo "$result"
}

# Function to discover all available addons using manifestoo (OCA style)
discover_addons() {
    echo "Discovering all available addons using manifestoo..."

    # Fetch both the main addons and their dependencies, then concatenate
    ADDONS_LIST=$(manifestoo --select-addons-dir /opt/odoo/addons --select-exclude "$EXCLUDE" list --separator=,)

    # Remove base so it stays initialized only once
    ADDONS_LIST=$(remove_from_csv "$ADDONS_LIST" base)

    if [[ -z "$ADDONS_LIST" ]]; then
        echo "No additional addons discovered beyond base."
    else
        echo "Found addons: $(echo "$ADDONS_LIST" | tr ',' '\n' | wc -l) modules"
        echo "Addons list: $ADDONS_LIST"
    fi

    # Export the addons list for use in other functions
    export ADDONS_LIST
}

install_requirements() {
    find /opt/odoo/addons -name "requirements.txt" -not -path "*/symple_addons/*" -exec pip install --no-cache-dir -r {} \; 2>/dev/null || echo "No requirements.txt files found in addons"
    pip install "cryptography==37.0.0" "pyopenssl==22.0.0" "paramiko<3.0"
}

install_depends() {
    echo "Installing dependent addons..."
    DEPENDS_LIST=$(manifestoo --select-addons-dir /opt/odoo/addons --select-exclude "$EXCLUDE" list-depends --separator=,)
    DEPENDS_LIST=$(remove_from_csv "$DEPENDS_LIST" base)

    if [[ -z "$DEPENDS_LIST" ]]; then
        echo "No dependent addons to install."
        return 0
    fi

    echo "Installing $DEPENDS_LIST"

    python3 /opt/odoo/base/odoo-bin \
        -c /opt/odoo/odoo.conf \
        -d "$DB_NAME" \
        -i "$DEPENDS_LIST" \
        --stop-after-init \
        --log-level=info 2>&1 | tee /opt/odoo/logs/install.log
}

# Function to install all addons
install_all_addons() {
    echo "Installing all available addons..."

    if [[ -z "$ADDONS_LIST" ]]; then
        echo "No additional addons detected. Skipping."
        return 0
    fi

    echo "Installing $ADDONS_LIST"
    echo "See logs/test.log for detailed output"

    # REMOVED: --logfile argument
    # ADDED: 2>&1 (redirects stderr to stdout so tee captures it)
    python3 /opt/odoo/base/odoo-bin \
        -c /opt/odoo/odoo.conf \
        -d "$DB_NAME" \
        -i "$ADDONS_LIST" \
        --stop-after-init \
        --log-level=info \
        --test-enable 2>&1 | tee /opt/odoo/logs/test.log
}

install_base_module() {
    echo "Initializing base module..."
    python3 /opt/odoo/base/odoo-bin \
        -c /opt/odoo/odoo.conf \
        -d "$DB_NAME" \
        -i base \
        --stop-after-init \
        --log-level=info
}

activate_it_lang() {
    echo "Activating it_IT language..."
    python3 /opt/odoo/base/odoo-bin shell \
        -c /opt/odoo/odoo.conf \
        -d "$DB_NAME" <<'PYTHON'
lang = env['res.lang'].search([('code', '=', 'it_IT')], limit=1)
if lang:
    lang.active = True
else:
    env['res.lang']._activate_lang('it_IT')
PYTHON
}

# Set hardcoded database values
DB_HOST=postgres
DB_PORT=5432
DB_USER=odoo
DB_NAME=odoo
EXCLUDE="symple_address_city_and_province_it,symple_contacts_default_data,sorgenia_imperex_metadata"

# Export database variables for psql commands
export PGPASSWORD=${DB_PASSWORD:-odoo}


# Wait for database to be ready
install_requirements
wait_for_db

# Initialize core requirements before the rest of the stack
install_base_module
activate_it_lang

# Always discover and install/update addons
discover_addons

install_depends
install_all_addons
