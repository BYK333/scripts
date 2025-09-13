#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 14.04, 15.04, 16.04 and 18.04 (could be used for other version too)
# Author: Yahbuike Ibe
#-------------------------------------------------------------------------------
# This script will install middleware sync on your Ubuntu 24.04 server.
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-sync-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-sync-install.sh
# Execute the script to install Odoo:
# ./odoo-sync-install
################################################################################

# ====== Default Parameter Values ======
RUN_MODE="prod"      # default run mode, change to "prod" for production
MODE="normal"      # default mode
LOGFILTER=""       # default: no filtering

if [ $RUN_MODE = "dev" ]; then
  OE_USER=$USER
  OE_HOME="$HOME/Yahjen/My_Devs/odoo/odoo_custom_addons"
  MIDDLEWARE_PATH="$OE_HOME/odoo-sync-middleware"
  MIDDLEWARE_CONFIG="middleware.dev.conf"
  ENVIRONMENT_FILE="$MIDDLEWARE_PATH/middleware.dev.conf"
  MIDDLEWARE_PYTHON_PATH="$HOME/.pyenv/versions/odoo-middleware/bin/python -u"
else
  OE_USER="odoo_sync"
  OE_HOME="/$OE_USER"
#  MIDDLEWARE_PATH="$OE_HOME/odoo-sync-middleware"
  MIDDLEWARE_PATH="$OE_HOME/"
  MIDDLEWARE_CONFIG="${OE_USER}-server.conf"
  ENVIRONMENT_FILE="/etc/$OE_USER/$MIDDLEWARE_CONFIG"
  SERVER_WORKERS=2
fi

MIDDLEWARE_DOMAIN_NAME="sfodoosyncv1.yahjenresourcesltd.com" # change to your domain
ADMIN_EMAIL="y.ibe@yahjenresourcesltd.com"  # for certbot etc
MIDDLEWARE_PORT="8800"


if [ $RUN_MODE = "dev" ]; then
    # Store PIDs of started processes
    PIDS=()

    # Function to kill all child processes on script exit
    cleanup() {
        echo "Stopping all child processes..."
        for pid in "${PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                wait "$pid"
            fi
        done
        exit 0
    }

    # Trap signals (Ctrl+C or PyCharm stop)
    trap cleanup SIGINT SIGTERM

    # ====== Parse Named Parameters ======
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -mode|--mode) MODE="$2"; shift ;;
            -log-filter|--log-filter) LOGFILTER="$2"; shift ;;
            *) echo "Unknown parameter: $1"; exit 1 ;;
        esac
        shift
    done

    # Convert comma-separated log filters into regex pattern
    # e.g., "INFO,DEBUG" → "(INFO|DEBUG)"
    if [[ -n "$LOGFILTER" ]]; then
        LOGFILTER_PATTERN="($(echo "$LOGFILTER" | sed 's/,/|/g'))"
    else
        LOGFILTER_PATTERN=""
    fi

    # ====== Colors ======
    NC='\033[0m'
    CYAN='\033[0;36m'
    Purple='\033[0;35m'
    Green='\033[0;32m'        # Green
    Yellow='\033[0;33m'
    BBlue='\033[1;34m'
    BRed='\033[1;31m'
    ODOO_BASE_COLOR=$BBlue
    ODOO_POS_COLOR=$BRed
    FASTAPI_COLOR=$Green
    WORKER_COLOR=$Yellow


    # ====== Paths ======
    # ODOO SETUPS **** ------------------------------------------
    ODOO14_PYTHON_PATH="/home/byk33/.pyenv/versions/3.7.9/envs/sofresh_odoo/bin/python -u"

    #primary odoo setup
    SOFRESH_ODOO14_BASE_BIN="${ODOO14_PYTHON_PATH} /home/byk33/Yahjen/My_Devs/odoo/odoo_versions/base/14/odoo-bin"
    SOFRESH_ODOO14_BASE_CONF="/etc/sofresh_25mar25.conf"

    #secondary odoo setup(for pos)
    SOFRESH_ODOO14_POS_BIN="${ODOO14_PYTHON_PATH} /home/byk33/Yahjen/My_Devs/odoo/odoo_versions/base/14/odoo-bin"
    SOFRESH_ODOO14_POS_CONF="/etc/sofresh_25mar25_pos.conf"

    # For generating the sync models
    MODELS_BUILD_PATH="/home/byk33/Yahjen/My_Devs/odoo/odoo_custom_addons/myScripts/odoo/generate_odoo_sync_models.py"
    MODELS_BUILD_CMD="$ODOO14_PYTHON_PATH $MODELS_BUILD_PATH"
    #----  **** ------------------------------------------

    # ====== Function to Prefix Logs with Color and Filter ======
    prefix_logs() {
        local prefix=$1
        local color=$2
        local log_levels="INFO|DEBUG|ERROR|WARNING|CRITICAL"  # extend as needed

        while IFS= read -r line; do
            #current timestamp in desired format
            local ts
            ts=$(date +"%Y-%m-%d %H:%M:%S")

            # Check if line contains any known log level keyword
            if [[ "$line" =~ $log_levels ]]; then
                # It's a "log" line — color normally
                if [[ -z "$LOGFILTER_PATTERN" ]] || ! [[ "$line" =~ $LOGFILTER_PATTERN ]]; then
                    echo -e "${color}[$prefix]$line${NC}"
                fi
            else
                # It's probably a print statement or unstructured output — color differently
                echo -e "${color}[$prefix][$ts]${NC} $line"
            fi
        done
    }

    FASTAPI_CMD="$MIDDLEWARE_PYTHON_PATH -m uvicorn main:app --reload --port $MIDDLEWARE_PORT"
    WORKER_CONF="$MIDDLEWARE_PATH/worker.py"

    echo -e "${Yellow}🚀 Starting in DEVELOPMENT mode=${MODE}...${NC}"

    # ====== Kill Existing Instances ======
    pkill -f "odoo-bin" 2>/dev/null
    pkill -f "uvicorn" 2>/dev/null
    pkill -f "worker.py"

    # ====== Start Services ======
    # Modes
    case "$MODE" in
        update-both)
            echo -e "${CYAN}Generating sync models...${Purple}"
            $MODELS_BUILD_CMD

            echo -e "${CYAN}Updating SF-BASE...${Purple}"
            pkill -f "$SOFRESH_ODOO14_BASE_BIN"
            ($SOFRESH_ODOO14_BASE_BIN -c "$SOFRESH_ODOO14_BASE_CONF" -d sofresh_25jun25 -u byk33_sync --stop-after-init 2>&1 | prefix_logs "SF-BASE UPDATE" "$Yellow")
    #        ($SOFRESH_ODOO14_BASE_BIN -c "$SOFRESH_ODOO14_BASE_CONF" -d sofresh_25jun25 -u all --stop-after-init 2>&1 | prefix_logs "SF-BASE UPDATE" "$Yellow")

            echo -e "${CYAN}Updating SF-POS...${Purple}"
            pkill -f "$SOFRESH_ODOO14_POS_BIN"
            ($SOFRESH_ODOO14_POS_BIN -c "$SOFRESH_ODOO14_POS_CONF" -d sf_pos_18 -u byk33_sync --stop-after-init 2>&1 | prefix_logs "SF-POS UPDATE" "$Purple")
    #        ($SOFRESH_ODOO14_POS_BIN -c "$SOFRESH_ODOO14_POS_CONF" -d sf_pos_1 -u all --stop-after-init 2>&1 | prefix_logs "SF-POS UPDATE" "$Purple")
            ;;
        update-base)
            echo -e "${CYAN}Generating sync models...${Purple}"
            $MODELS_BUILD_CMD

            echo -e "${CYAN}Updating SF-BASE...${Purple}"
            pkill -f "$SOFRESH_ODOO14_BASE_BIN"
            ($SOFRESH_ODOO14_BASE_BIN -c "$SOFRESH_ODOO14_BASE_CONF" -d sofresh_25jun25 -u byk33_sync --stop-after-init 2>&1 | prefix_logs "SF-BASE UPDATE" "$Yellow")
            ;;
        update-pos)
            echo -e "${CYAN}Generating sync models...${Purple}"
            $MODELS_BUILD_CMD

            echo -e "${CYAN}Updating SF-POS...${Purple}"
            pkill -f "$SOFRESH_ODOO14_POS_BIN"
            ($SOFRESH_ODOO14_POS_BIN -c "$SOFRESH_ODOO14_POS_CONF" -d sf123 -u byk33_sync --stop-after-init 2>&1 | prefix_logs "SF-POS UPDATE" "$Purple")
            ;;
    esac

    # Start Odoo base
    ($SOFRESH_ODOO14_BASE_BIN -c "$SOFRESH_ODOO14_BASE_CONF" -d sofresh_25jun25 --limit-time-cpu 90 --limit-time-real 640 2>&1 | prefix_logs "SF-BASE" "$ODOO_BASE_COLOR") &
    PIDS+=($!)

    # Start Odoo pos
    #($SOFRESH_ODOO14_POS_BIN -c "$SOFRESH_ODOO14_POS_CONF" --db-filter .*sf_pos.* --limit-time-cpu 90 --limit-time-real 640 2>&1 | prefix_logs "SF-POS" "$ODOO_POS_COLOR$") &
    ($SOFRESH_ODOO14_POS_BIN -c "$SOFRESH_ODOO14_POS_CONF" -d sf_pos_18 --limit-time-cpu 90 --limit-time-real 640 2>&1 | prefix_logs "SF-POS" "$ODOO_POS_COLOR$") &
    PIDS+=($!)

    # Start FastAPI
    (cd $MIDDLEWARE_PATH && ${FASTAPI_CMD[@]} 2>&1 | prefix_logs "FASTAPI" "$Green") &
    PIDS+=($!)

    # Start Redis worker
    NUM_WORKERS=2
    for i in $(seq 1 $NUM_WORKERS); do
        echo "🔁 Starting worker $i...$WORKER_CONF"
        ($MIDDLEWARE_PYTHON_PATH "$WORKER_CONF" 2>&1 | prefix_logs "REDIS Worker $i" "$WORKER_COLOR") &
        PIDS+=($!)
    done

    wait
elif [[ "$RUN_MODE" == "prod" ]]; then
    echo -e "\n---- System preparation: Update Server and Install Dependencies ----"
    sudo apt-get update && sudo apt-get install -y git python3 python3-pip python3-venv python3-dev build-essential \
    wget redis-server nginx ufw fail2ban certbot python3-certbot-nginx

    #--------------------------------------------------
    # Create ODOO SYNC system user
    #--------------------------------------------------
    if id "$OE_USER" &>/dev/null; then
      echo "User $OE_USER already exists, skipping..."
    else
      echo -e "\n---- Creating $OE_USER system user ----"
      sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO SYNC USER' --group $OE_USER
      sudo adduser $OE_USER sudo
    fi

    #--------------------------------------------------
    # MIDDLEWARE SETUPS ****-
    #--------------------------------------------------
    echo -e "\n==== pull the middleware repo ===="
    git clone https://github.com/BYK333/odoo_sync.git $OE_HOME/

    echo -e "\n---- Install python packages/requirements ----"
    #sudo -H pip3 install -r $MIDDLEWARE_PATH/requirements.txt #sets package global

    # create venv if not exists
    if [ ! -d "$MIDDLEWARE_PATH/venv" ]; then
        python3 -m venv "$MIDDLEWARE_PATH/venv"
    fi
    # activate venv and install packages
    source "$MIDDLEWARE_PATH/venv/bin/activate"
    pip install --upgrade pip3
    pip install -r "$MIDDLEWARE_PATH/requirements.txt"
    deactivate
    MIDDLEWARE_BIN_PATH="$MIDDLEWARE_PATH/venv/bin"
    MIDDLEWARE_PYTHON_PATH="$MIDDLEWARE_PATH/venv/bin/python3"

    echo -e "\n---- Setting permissions on home folder and log directory ----"
    sudo chown -R $OE_USER:$OE_USER $OE_HOME/*

    #** Setting up log directories ----"
    MIDDLEWARE_LOG_DIRECTORY="/var/log/${OE_USER}_sync"
    if [ -d "$MIDDLEWARE_LOG_DIRECTORY" ]; then
        # Directory exists, check ownership
        OWNER=$(stat -c "%U" "$MIDDLEWARE_LOG_DIRECTORY")
        if [ "$OWNER" = "$OE_USER" ]; then
            echo "\n---- ✔ Log directory $MIDDLEWARE_LOG_DIRECTORY already exists and is owned by $OE_USER"
        else
            echo "\n---- ⚠ Log directory exists but not owned by $OE_USER, fixing..."
            sudo chown -R $OE_USER:$OE_USER "$MIDDLEWARE_LOG_DIRECTORY"
        fi
    else
        echo "\n---- ➕ Creating log directory $MIDDLEWARE_LOG_DIRECTORY"
        sudo mkdir -p "$MIDDLEWARE_LOG_DIRECTORY"
        sudo chown -R $OE_USER:$OE_USER "$MIDDLEWARE_LOG_DIRECTORY"
    fi

    #--------------------------------------------------
    # #create server config files and services
    #--------------------------------------------------
    echo -e "* Creating server config file"
    sudo mv "$OE_HOME/odoo-sync-middleware/middleware.conf" $ENVIRONMENT_FILE
    sudo chown $OE_USER:$OE_USER $ENVIRONMENT_FILE
    sudo chmod 640 $ENVIRONMENT_FILE

    #create services
    echo -e "\n---- Creating $OE_USER fastapi service ----"
    FASTAPI_SERVICE="/etc/systemd/system/${OE_USER}_fastapi.service"
    #--log-level info"
    FASTAPI_CMD=(
      "${MIDDLEWARE_BIN_PATH}/gunicorn main:app
      -k uvicorn.workers.UvicornWorker
      --bind 127.0.0.1:${MIDDLEWARE_PORT}
      --workers ${SERVER_WORKERS}"
    )
    sudo tee "$FASTAPI_SERVICE" > /dev/null <<EOF
[Unit]
Description=Gunicorn FastAPI for Odoo Sync
After=network.target

[Service]
User=$OE_USER
WorkingDirectory=$MIDDLEWARE_PATH
EnvironmentFile=$ENVIRONMENT_FILE
ExecStart=${MIDDLEWARE_BIN_PATH}/gunicorn main:app \
    -k uvicorn.workers.UvicornWorker \
    --bind 127.0.0.1:${MIDDLEWARE_PORT} \
    --workers ${SERVER_WORKERS}
Restart=always
StandardOutput=file:$MIDDLEWARE_LOG_DIRECTORY/fastapi.log
StandardError=file:$MIDDLEWARE_LOG_DIRECTORY/fastapi_error.log

[Install]
WantedBy=multi-user.target
EOF

    echo -e "\n---- Creating $OE_USER worker service ----"
    WORKER_SERVICE="/etc/systemd/system/${OE_USER}_worker@.service"
    sudo tee "$WORKER_SERVICE" > /dev/null <<EOF
[Unit]
Description=Redis Worker for Odoo Sync (Instance %i)
After=network.target

[Service]
User=$OE_USER
WorkingDirectory=$MIDDLEWARE_PATH
EnvironmentFile=$ENVIRONMENT_FILE
ExecStart=$MIDDLEWARE_PYTHON_PATH worker.py
Restart=always
StandardOutput=file:$MIDDLEWARE_LOG_DIRECTORY/worker_%i.log
StandardError=file:$MIDDLEWARE_LOG_DIRECTORY/worker_%i_error.log

[Install]
WantedBy=multi-user.target
EOF

    echo -e "\n---- Creating $OE_USER (FastAPI + Worker) service ----"
    MIDDLEWARE_SERVICE="/etc/systemd/system/${OE_USER}.service"
    sudo tee "$MIDDLEWARE_SERVICE" > /dev/null <<EOF
[Unit]
Description=Odoo Sync Middleware (FastAPI + Worker)
Wants=${OE_USER}_fastapi.service ${OE_USER}_worker@.service
After=network.target ${OE_USER}_fastapi.service ${OE_USER}_worker@.service

[Install]
WantedBy=multi-user.target
EOF

    #--------------------------------------------------
    # NGINX Setup for FastAPI Middleware
    #--------------------------------------------------
    if [ -z "$MIDDLEWARE_DOMAIN_NAME" ]; then
        echo "❌ Domain name not provided. Usage: setup_nginx <domain>"
        return 1
    fi

    echo -e "\n---- Setting up Nginx reverse proxy for $MIDDLEWARE_DOMAIN_NAME ----"
    NGINX_CONF="/etc/nginx/sites-available/$MIDDLEWARE_DOMAIN_NAME"
    CONFIG_FILE=$MIDDLEWARE_PATH
    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $MIDDLEWARE_DOMAIN_NAME;

    location / {
        proxy_pass         http://127.0.0.1:${MIDDLEWARE_PORT};
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOF
    # Enable site
    sudo ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$MIDDLEWARE_DOMAIN_NAME"

    # Test config and reload
    sudo nginx -t && sudo systemctl reload nginx

    echo -e "✅ Nginx reverse proxy for $MIDDLEWARE_DOMAIN_NAME configured."

    # Obtain SSL cert via certbot
    echo -e "\n---- Obtaining SSL certificate ----"
    sudo certbot --nginx -d "$MIDDLEWARE_DOMAIN_NAME" --non-interactive --agree-tos -m $ADMIN_EMAIL
    echo -e "✅ SSL certificate installed for https://$MIDDLEWARE_DOMAIN_NAME"

    # Reload systemd to register changes
    sudo systemctl daemon-reload

    # Enable and start FastAPI + Worker services
    sudo systemctl enable --now ${OE_USER}.service

    echo "✅ Production services deployed and running."
    echo "   - Logs: journalctl -u odoo_sync_fastapi -f"
    echo "   - Logs worker1: journalctl -u odoo_sync_worker@1 -f"
else
    echo "❌ Unknown mode: $RUN_MODE"
    exit 1
fi