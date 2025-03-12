#!/bin/bash
check_dependencies() {
    local missing_deps=()
    for dep in "$@"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Missing dependencies: ${missing_deps[*]}"
        echo "Please install them and try again."
        exit 1
    fi
}

check_dependencies yq sftp lz4 gpg curl tar

config_file="config.yml"
echo $config_file

read_config() {
    yq e "$1" "$config_file"
}

execution_path=$(pwd)
base_local_path=$(read_config '.global.local_path')
keep_backups=$(read_config '.global.keep_backups')
encrypt_password=$(read_config '.global.encrypt_password')
webhook_url=$(read_config '.global.webhook_url')

send_notification() {
    if [ "$webhook_url" != "null" ] && [ -n "$webhook_url" ]; then
        curl -k -X GET -H "Content-Type: application/json" -d "{\"message\":\"$1\"}" "$webhook_url"
    else
        echo "$1"
    fi
}

cleanup_old_backups() {
    local host_name="$1"
    if [ -n "$keep_backups" ] && [ "$keep_backups" -gt 0 ]; then
        
        cd $base_local_path
        ls -1t ${host_name}_*.tar.lz4.gpg | tail -n +$((keep_backups + 1)) | xargs -d '\n' rm -f --
        cd $execution_path
    fi
}

add_ssh_known_hosts() {
    for host in $(read_config '.hosts[].host'); do
        ssh-keyscan -H $host >> ${HOME}/.ssh/known_hosts 2> /dev/null
    done
}

backup_host() {
    local host_name="$1"
    local key_path="$2"
    local user="$3"
    local backup_host="$4"
    local remote_paths="$5"

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local temp_path="/tmp/backup_${host_name}_${timestamp}"
    local local_path="${base_local_path}/${host_name}_${timestamp}.tar.lz4.gpg"

    mkdir -p "$temp_path"
    mkdir -p "$base_local_path"

    add_ssh_known_hosts

    send_notification "Backup started for $host_name"

    sftp -i "$key_path" "$user@$backup_host" <<EOF
$(for path in $remote_paths; do
    echo "get -r $path $temp_path/$(basename "$path")"
done)
EOF

    if [ $? -eq 0 ]; then
        tar -cf - -C "$temp_path" . | lz4 -z | gpg --batch --yes --passphrase "$encrypt_password" -c -o "$local_path"
        rm -rf "$temp_path"
        cleanup_old_backups "$host_name"
        send_notification "Backup completed successfully for $host_name"
    else
        rm -rf "$temp_path"
        send_notification "Error: Backup failed for $host_name"
        return 1
    fi
}

restore_host() {
    local host_name="$1"
    local key_path="$2"
    local user="$3"
    local restore_host="$4"
    local remote_paths="$5"

    # Find the latest backup file
    local latest_backup=$(ls -t "${base_local_path}/${host_name}"*.tar.lz4.gpg | head -n1)

    if [ -z "$latest_backup" ]; then
        send_notification "Error: No backup found for $host_name"
        return 1
    fi

    local temp_path="/tmp/restore_${host_name}_$(date +"%Y%m%d_%H%M%S")"
    mkdir -p "$temp_path"
    add_ssh_known_hosts
    send_notification "Restore started for $host_name"

    # Decrypt and extract the backup
    gpg --batch --yes --passphrase "$encrypt_password" -d "$latest_backup" | lz4 -d | tar -xv -C "$temp_path"


    if [ $? -eq 0 ]; then
        for path in $remote_paths; do
            ssh -i "$key_path" "$user@$restore_host" "rm -rf $path && mkdir -p $path"
            if [ $? -ne 0 ]; then
                send_notification "Error: Failed to remove/recreate directory $path on $host_name"
                rm -rf "$temp_path"
                return 1
            fi
        done
        
        
        # Upload the files via SFTP
        sftp -i "$key_path" "$user@$restore_host" <<EOF
$(for path in $remote_paths; do
    #echo "mkdir -p $(dirname "$path")"
    echo "cd $path"
    echo "put -r $temp_path/$(basename "$path")/*"
    echo "cd /"
done)
EOF

        if [ $? -eq 0 ]; then
            rm -rf "$temp_path"
            send_notification "Restore completed successfully for $host_name"
        else
            rm -rf "$temp_path"
            send_notification "Error: Restore failed during file transfer for $host_name"
            return 1
        fi
    else
        rm -rf "$temp_path"
        send_notification "Error: Restore failed during decryption/extraction for $host_name"
        return 1
    fi
}

read_host() {
    name=$(read_config ".hosts[$i].name")
    key_path=$(read_config ".hosts[$i].key_path")
    user=$(read_config ".hosts[$i].user")
    host=$(read_config ".hosts[$i].host")
    remote_paths=$(read_config ".hosts[$i].remote_paths[]" | grep -v '^$')    
}

# Main execution for backup
backup() {
    send_notification "Starting backup process"

    hosts_count=$(read_config '.hosts | length')
    for i in $(seq 0 $((hosts_count - 1))); do
        read_host
        backup_host "$name" "$key_path" "$user" "$host" "$remote_paths"
    done

    send_notification "Backup process completed"
}

# Main execution for restore
restore() {
    send_notification "Starting restore process"

    hosts_count=$(read_config '.hosts | length')
    for i in $(seq 0 $((hosts_count - 1))); do
        read_host
        restore_host "$name" "$key_path" "$user" "$host" "$remote_paths"
    done

    send_notification "Restore process completed"
}

# Main script
case "$1" in
    backup)
        backup
        ;;
    restore)
        restore
        ;;
    *)
        echo "Usage: $0 {backup|restore}"
        exit 1
        ;;
esac

exit 0