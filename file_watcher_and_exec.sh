#!/bin/bash
# ==============================================================================
# 스크립트명: smart_watcher_and_exec.sh (가칭)
# 설명:
#   '디바운스(Debounce)' 로직이 적용된 파일 감시 스크립트.
#   지정된 디렉토리(MONITOR_DIR)에 파일 생성 이벤트가 감지되면,
#   타임스탬프를 갱신하고 "대기 함수"를 실행합니다.
#
#   "대기 함수"는 마지막 파일 이벤트가 발생한 시간으로부터
#   DELAY(예: 180초)가 지날 때까지(즉, 180초간 조용할 때까지) 기다린 후,
#   메인 스크립트(SCRIPT_TO_RUN)를 실행합니다.
#
#   파일 이벤트가 발생할 때마다 타임스탬프가 갱신되어 대기 시간이 "재설정"됩니다.
#
# 전제 조건:
#   - 'inotify-tools' 패키지가 설치되어 있어야 합니다.
# ==============================================================================

# --- 설정 (Configuration) ---

MONITOR_DIR="/dicom/import"
SCRIPT_TO_RUN="/data/storescu.sh"
DELAY=180 # 180초 (3분)
LOG_DIR="/data/log"

# --- 내부 관리 파일/디렉토리 (Internal State) ---
# 이 파일들은 모니터링 디렉토리 외부에 위치해야 합니다.

# 1. 락 디렉토리 (원자적 생성을 위해 파일 대신 디렉토리 사용)
#    'wait_and_execute' 함수가 이미 실행 중인지 확인하는 표식
LOCK_DIR="/tmp/dicom_waiter.lockdir"

# 2. 타임스탬프 파일
#    마지막 파일 이벤트가 감지된 시간을 Unixtime(초)으로 저장
TIMESTAMP_FILE="/tmp/dicom_last_event.timestamp"

# --- 함수 정의 (Functions) ---

# 함수: wait_and_execute
# 설명: 백그라운드에서 실행되며, 타임스탬프를 주기적으로 확인합니다.
#       마지막 이벤트 시간으로부터 DELAY가 경과하면 메인 스크립트를 실행합니다.
wait_and_execute() {
    # 이 함수는 $LOCK_DIR 이 생성된 직후 백그라운드로 실행됩니다.
    echo "[Waiter] Waiter process started. Waiting for ${DELAY}s of inactivity..."

    while true; do
        # 5초마다 타임스탬프를 확인
        sleep 5

        # TIMESTAMP_FILE이 없으면 (이미 처리되었거나 오류) 루프 종료
        if [ ! -f "$TIMESTAMP_FILE" ]; then
            echo "[Waiter] Timestamp file not found. Assuming processed."
            break
        fi

        # 마지막 이벤트 시간과 현재 시간 비교
        LAST_EVENT_TIME=$(cat "$TIMESTAMP_FILE")
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_EVENT_TIME))

        # [핵심 로직] 마지막 이벤트 이후 DELAY 시간이 경과했는지 확인
        if [ $TIME_DIFF -ge $DELAY ]; then
            echo "[Waiter] $DELAY seconds of inactivity detected. Running script."

            # [1] 실행 전 타임스탬프 삭제 (다른 프로세스가 재실행하지 않도록)
            rm -f "$TIMESTAMP_FILE"

            # [2] 메인 스크립트 실행 및 로깅
            LOG_FILE_NAME=$(date "+%Y%m%d-%H%M%S").log
            mkdir -p "$LOG_DIR"
            bash "$SCRIPT_TO_RUN" &> "$LOG_DIR/$LOG_FILE_NAME"

            echo "[Waiter] Script finished. Releasing lock."

            # [3] 작업 완료 후 락 디렉토리 삭제
            #     이후 새로운 inotify 이벤트가 발생하면 락을 다시 잡고
            #     이 함수(waiter)를 새로 시작할 수 있습니다.
            rmdir "$LOCK_DIR"

            # [4] 대기 함수(waiter) 종료
            break
        # else
            # [시간 미경과]
            # TIME_DIFF가 DELAY보다 작으면 (아직 180초가 안 지났으면)
            # 루프가 계속 돌면서 5초 뒤에 다시 확인합니다.
        fi
    done
    echo "[Waiter] Waiter process finished."
}


# --- 메인 실행부 (Main Execution) ---

echo "[Watcher] Starting smart file monitoring on: $MONITOR_DIR"
echo "[Watcher] (Script will run after $DELAY seconds of inactivity)"

# 스크립트 시작 시, 이전 실행에서 남은 락/타임스탬프가 있다면 정리
rm -f "$TIMESTAMP_FILE"
rmdir "$LOCK_DIR" 2>/dev/null

# inotifywait로 'create' 이벤트 감시
inotifywait -m -r -e create "$MONITOR_DIR" | while read path action file; do
    echo "[Watcher] Detected $action on $file."

    # [1. 타이머 재설정]
    #    파일이 감지될 때마다 현재 시간을 타임스탬프 파일에 덮어씁니다.
    #    이것이 "타이머 재설정"의 핵심입니다.
    echo $(date +%s) > "$TIMESTAMP_FILE"

    # [2. 락(Lock) 확인]
    #    'mkdir'는 원자적(atomic) 연산입니다.
    #    디렉토리가 성공적으로 생성되면(아무도 락을 안 잡았으면) true를 반환합니다.
    #    이미 존재하면(다른 프로세스가 락을 잡았으면) false를 반환합니다.
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        # [3. 락 획득 성공]
        #    대기(waiter) 프로세스가 없으므로, 새로 시작합니다.
        echo "[Watcher] Lock acquired. Starting waiter process in background."
        wait_and_execute & # 백그라운드 실행
    else
        # [4. 락 획득 실패]
        #    이미 대기(waiter) 프로세스가 실행 중입니다.
        #    타임스탬프만 갱신했으므로, 기존 waiter가 이 시간을 보고
        #    타이머를 "재설정" (대기를 연장) 할 것입니다.
        echo "[Watcher] Waiter already active. Timer has been reset."
    fi
done