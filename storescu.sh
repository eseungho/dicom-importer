#!/bin/bash
# ==============================================================================
# 스크립트명: storescu.sh
# 설명:
#   지정된 디렉토리(DICOM_DIR)에서 '#PID-환자이름' 패턴의 하위 폴더를 찾아,
#   해당 폴더 내의 모든 DICOM 파일의 메타데이터(PatientID, PatientName)를
#   폴더명에 맞게 수정한 후, 설정된 PACS 서버로 C-STORE 전송을 수행합니다.
#   전송 완료 후, 처리된 파일들을 타임스탬프가 찍힌 아카이브 폴더로 이동시킵니다.
#
# 전제 조건:
#   - DCMTK (dcm4che ToolKit)가 설치되어 있어야 합니다. (dcmodify, storescu 명령어 사용)
#   - 스크립트 실행 계정은 DICOM_DIR, ARCHIVE_DIR, LOG_FILE에 대한
#     읽기/쓰기/실행 권한이 있어야 합니다.
# ==============================================================================

# --- 설정 (Configuration) ---

# 1. PACS 서버 설정
#PACS_SERVER_IP="host.docker.internal" # 도커 환경인 경우
PACS_SERVER_IP="127.0.0.1"            # PACS 서버의 IP 주소
PACS_SERVER_PORT="11112"              # PACS 서버의 포트
PACS_AET="DCM4CHEE"                   # PACS 서버의 AET (Application Entity Title)

# 2. 디렉토리 경로 설정
# DICOM 파일을 읽어올 원본 디렉토리
DICOM_DIR="/dicom/import"
# 처리가 완료된 파일을 이동시킬 아카이브 최상위 디렉토리
ARCHIVE_DIR="/dicom/archived"

# 3. 로그 파일 경로
LOG_FILE="/data/log.log"

# --- 로깅 설정 ---

# 스크립트의 표준 출력(stdout)과 표준 에러(stderr)를
# 로그 파일에 추가(append)하면서 동시에 터미널에도 출력합니다.
# 스크립트의 모든 echo 및 명령어 실행 결과가 로그에 기록됩니다.
exec > >(tee -a "${LOG_FILE}") 2>&1

# --- 함수 정의 (Functions) ---

# 함수: modify_dicom_metadata
# 설명: 단일 DICOM 파일의 메타데이터(Patient ID, Patient Name)를 수정합니다.
# 인자: $1 (file: 파일 경로), $2 (pid: 환자 ID), $3 (name: 환자 이름)
modify_dicom_metadata() {
    local file=$1
    local pid=$2
    local name=$3

    # 파일의 128바이트 오프셋에서 "DICM" 매직 넘버를 확인하여 DICOM 파일인지 검사합니다.
    # (head -c 132 | tail -c 4)
    if [[ $(head -c 132 "$file" | tail -c 4) == "DICM" ]]; then
        echo "  [INFO] Modifying DICOM file: $file"
        # dcmodify: DICOM 메타데이터 수정 명령어
        # -ie : 읽기 오류 무시 (Ignore read errors)
        # -nb : 원본 파일 백업 생성 안 함 (No backup)
        # -v  : 상세 출력 (Verbose)
        # -m  : 메타데이터 수정 (Modify)
        #       (0010,0020) = Patient ID
        #       (0010,0010) = Patient Name
        dcmodify -ie -nb -v -m "(0010,0020)=${pid}" -m "(0010,0010)=${name}" "$file"
    else
        echo "  [WARN] Not a DICOM file: $file. Skipping."
    fi
}

# 함수: process_files_in_folder
# 설명: 특정 폴더와 그 하위의 모든 파일들을 대상으로 메타데이터 수정을 호출합니다.
# 인자: $1 (folder: 대상 폴더), $2 (pid: 환자 ID), $3 (name: 환자 이름)
process_files_in_folder() {
    local folder=$1
    local pid=$2
    local name=$3

    # find 명령어로 대상 폴더($folder) 내의 모든 '파일(-type f)'을 찾습니다.
    # 'while read file' 구문을 통해 각 파일 경로를 'file' 변수에 담아 반복 처리합니다.
    find "$folder" -type f | while read file; do
        modify_dicom_metadata "$file" "$pid" "$name"
    done
}

# 함수: process_folder
# 설명: 상위 폴더의 이름 규칙을 분석하여 PID와 이름을 추출하고,
#       파일 처리 함수(process_files_in_folder)를 호출합니다.
# 인자: $1 (folder: 대상 폴더 경로)
process_folder() {
    local folder=$1
    echo "[INFO] Processing folder: $folder"

    # 'basename' 명령어로 전체 경로에서 마지막 폴더 이름만 추출합니다.
    local folder_name=$(basename "$folder")

    # 정규 표현식 매칭: 폴더 이름이 '#<숫자>-<문자열>' 형식인지 확인합니다.
    # 예: #12345-HongGildong
    # ^\# : '#'으로 시작
    # ([0-9]+) : 하나 이상의 숫자 (그룹 1: PID)
    # - : 하이픈 구분자
    # ([\#^A-Za-z0-9]+) : 이름 문자열 (그룹 2: Name). #, ^, 영문, 숫자 허용.
    if [[ $folder_name =~ ^\#([0-9]+)-([\#^A-Za-z0-9]+)$ ]]; then
        # BASH_REMATCH 배열에 매칭된 결과가 저장됩니다.
        # [0] = 전체 매칭 문자열, [1] = 첫 번째 괄호 그룹, [2] = 두 번째 괄호 그룹
        local pid=${BASH_REMATCH[1]}
        local name=${BASH_REMATCH[2]}

        echo "  [INFO] Pattern matched. PID: [$pid], Name: [$name]"
        # 해당 폴더 내 모든 파일에 대해 메타데이터 수정 함수 호출
        process_files_in_folder "$folder" "$pid" "$name"
    else
        echo "  [WARN] Folder name pattern does not match. Skipping folder: $folder"
    fi
}

# --- 메인 실행부 (Main Execution) ---

echo "================================================="
echo "$(date): Script execution started."
echo "================================================="

# --- 1. 메타데이터 수정 (Metadata Modification) ---
echo "[PHASE 1] Starting DICOM metadata modification..."

# $DICOM_DIR 바로 아래의 모든 항목(* )에 대해 반복합니다.
for folder in "$DICOM_DIR"/*; do
    # 항목이 디렉토리(-d)인지 확인합니다.
    if [ -d "$folder" ]; then
        process_folder "$folder"
    fi
done

echo "[PHASE 1] All DICOM files metadata modified."
echo "-------------------------------------------------"

# --- 2. PACS 전송 (DICOM C-STORE) ---
echo "[PHASE 2] Executing storescu (DICOM Send)..."

# storescu: DICOM C-STORE (전송) 명령어
# -c : AET@IP:PORT 형식으로 대상 PACS를 지정합니다.
# ${DICOM_DIR} : 전송할 파일 또는 디렉토리를 지정합니다. (하위 디렉토리 포함)
storescu -c ${PACS_AET}@${PACS_SERVER_IP}:${PACS_SERVER_PORT} ${DICOM_DIR}

echo "[PHASE 2] storescu execution completed."
echo "-------------------------------------------------"

# --- 3. 아카이빙 (Archiving) ---
echo "[PHASE 3] Starting archiving process..."

# 현재 날짜와 시간을 yyyymmdd_hhmmss 형식으로 변수에 저장합니다.
CURRENT_DATE_TIME=$(date +"%Y%m%d_%H%M%S")

# 아카이브할 최종 목적지 경로를 설정합니다.
DESTINATION="$ARCHIVE_DIR/$CURRENT_DATE_TIME"

# $DICOM_DIR 내에 파일(하위 폴더 포함)이 하나라도 있는지(-n) 확인합니다.
# find ... -type f : 모든 파일을 찾습니다.
# [ -n "..." ] : 문자열이 비어있지 않으면 (즉, 파일이 하나라도 있으면) 참(True)
if [ -n "$(find "$DICOM_DIR" -type f)" ]; then
    # 아카이브 디렉토리 생성 (-p: 상위 디렉토리도 함께 생성)
    echo "  [INFO] Creating archive directory: $DESTINATION"
    mkdir -p "$DESTINATION"

    # $DICOM_DIR 내의 모든 파일/폴더(*)를 $DESTINATION 으로 이동(mv)합니다.
    # 이 작업으로 $DICOM_DIR 는 비워지게 됩니다.
    echo "  [INFO] Moving files from $DICOM_DIR to $DESTINATION"
    mv "$DICOM_DIR"/* "$DESTINATION"

    echo "  [INFO] Files successfully moved to $DESTINATION"
else
    echo "  [INFO] No files to move in $DICOM_DIR. Skipping archive."
fi

echo "[PHASE 3] Archiving process completed."
echo "================================================="
echo "$(date): Script execution finished."
echo "================================================="
echo "" # 로그 구분을 위한 공백 라인