# SBaTo
SBaTo (SFTP backup tool) is a bash script to perform backups of remote servers via SSH. The tool also manages restoration from the backups.

## Installation using Docker
### docker-compose.yml
Configure the docker-compose file with:
- the path to the config file
- the path to the SSH keys
- the pass to the backups destination

### config.yml
`global`:
- `local_path`: Specifies the local directory where backups will be stored.
- `keep_backups`: Defines the number of backups to retain.
- `encrypt_password`: Set your secure encryption password here.
- `webhook_url` (Optional): If needed, provide a webhook URL for notifications.

`hosts`:
- `name`: Name of the server for the script
- `key_path`: Defines the place of the private SSH key to use for the server
- `user`: Defines the name of the remote user to use on the server
- `remote_path`: Lists the paths to backup

### Running
- Build locally for 
```bash
docker compose -f docker-compose-local-backup.yml up
```
- Pull from Docker Hub
```bash
docker compose -f docker-compose-remote-backup.yml up
```
- Build locally
```bash
docker compose -f docker-compose-local-restore.yml up
```
- Pull from Docker Hub
```bash
docker compose -f docker-compose-remote-restore.yml up
```

## Usage
### Docker
#### One shot usage
```bash
docker start sbato
```

#### Regular backup
```bash
crontab -e
0 0 * * * docker start sbato >> /var/log/sbato.log 2>&1
```

### Bash
#### Backup
```bash
chmod a+x main.sh
./main.sh backup
```
#### Restore 
```bash
chmod a+x main.sh
./main.sh restore --all # restores all
./main.sh restore -n name # restores one
```

## License
[MIT](https://choosealicense.com/licenses/mit/)