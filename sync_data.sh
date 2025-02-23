#!/bin/bash

# 检查环境变量
if [ -z "$HF_TOKEN" ] || [ -z "$DATASET_ID" ]; then
    echo "Starting without backup functionality - missing HF_TOKEN or DATASET_ID"
    exec python main.py
fi

# 登录HuggingFace (使用环境变量方式避免交互问题)
export HUGGING_FACE_HUB_TOKEN=$HF_TOKEN

# 同步函数
sync_data() {
    while true; do
        echo "Starting sync process at $(date)"
        
        # 创建临时压缩文件
        cd /app
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_file="backup_${timestamp}.tar.gz"
        
        tar -czf "/tmp/${backup_file}" data/
        
        python3 -c "
from huggingface_hub import HfApi
import os
def manage_backups(api, repo_id, max_files=50):
    files = api.list_repo_files(repo_id=repo_id, repo_type='dataset')
    backup_files = [f for f in files if f.startswith('backup_') and f.endswith('.tar.gz')]
    backup_files.sort()
    
    if len(backup_files) >= max_files:
        files_to_delete = backup_files[:(len(backup_files) - max_files + 1)]
        for file_to_delete in files_to_delete:
            try:
                api.delete_file(path_in_repo=file_to_delete, repo_id=repo_id, repo_type='dataset')
                print(f'Deleted old backup: {file_to_delete}')
            except Exception as e:
                print(f'Error deleting {file_to_delete}: {str(e)}')
try:
    api = HfApi()
    api.upload_file(
        path_or_fileobj='/tmp/${backup_file}',
        path_in_repo='${backup_file}',
        repo_id='${DATASET_ID}',
        repo_type='dataset'
    )
    print('Backup uploaded successfully')
    
    manage_backups(api, '${DATASET_ID}')
except Exception as e:
    print(f'Backup failed: {str(e)}')
"
        # 清理临时文件
        rm -f "/tmp/${backup_file}"
        
        # 设置同步间隔
        SYNC_INTERVAL=${SYNC_INTERVAL:-7200}
        echo "Next sync in ${SYNC_INTERVAL} seconds..."
        sleep $SYNC_INTERVAL
    done
}

# 恢复函数
restore_latest() {
    echo "Attempting to restore latest backup..."
    python3 -c "
try:
    from huggingface_hub import HfApi
    import os
    
    api = HfApi()
    files = api.list_repo_files('${DATASET_ID}', repo_type='dataset')
    backup_files = [f for f in files if f.startswith('backup_') and f.endswith('.tar.gz')]
    
    if backup_files:
        latest = sorted(backup_files)[-1]
        api.hf_hub_download(
            repo_id='${DATASET_ID}',
            filename=latest,
            repo_type='dataset',
            local_dir='/tmp'
        )
        os.system(f'tar -xzf /tmp/{latest} -C /app')
        os.remove(f'/tmp/{latest}')
        print(f'Restored from {latest}')
    else:
        print('No backup found')
except Exception as e:
    print(f'Restore failed: {str(e)}')
"
}

# 主程序
(
    # 尝试恢复
    restore_latest
    
    # 启动同步进程
    sync_data &
    
    # 启动主应用
    exec python main.py
) 2>&1 | tee -a /app/data/backup.log