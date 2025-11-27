# DICOM Importer
DICOM 파일을 자동으로 감지하여 메타데이터를 수정하고 PACS 서버로 전송하는 Docker 기반 자동화 시스템입니다.

## 📋 목차
- [개요](#개요)
- [주요 기능](#주요-기능)
- [시스템 아키텍처](#시스템-아키텍처)
- [필수 요구사항](#필수-요구사항)
- [설치 및 설정](#설치-및-설정)
- [사용 방법](#사용-방법)
- [디렉토리 구조](#디렉토리-구조)
- [설정 커스터마이징](#설정-커스터마이징)
- [로그 및 모니터링](#로그-및-모니터링)
- [문제 해결](#문제-해결)

## 개요
DICOM Importer는 의료 영상 파일(DICOM)을 자동으로 처리하고 PACS(Picture Archiving and Communication System) 서버로 전송하는 솔루션입니다. 파일 감시 기능과 디바운스 로직을 통해 안정적이고 효율적인 배치 처리를 제공합니다.

## 주요 기능

### 1. **스마트 파일 감시 시스템**
- `inotify`를 활용한 실시간 파일 생성 감지
- 180초(3분) 디바운스 로직 적용
  - 파일이 계속 추가되는 동안 대기
  - 마지막 파일 추가 후 3분 경과 시 자동 실행
- 대량 파일 업로드 시 효율적인 배치 처리

### 2. **DICOM 메타데이터 자동 수정**
- 폴더명 기반 환자 정보 추출
- Patient ID 및 Patient Name 자동 업데이트
- DICOM 파일 유효성 검사 (DICM 매직 넘버 확인)

### 3. **PACS 서버 전송**
- DCMTK의 `storescu` 명령어를 통한 표준 DICOM C-STORE 전송
- 재귀적 디렉토리 전송 지원

### 4. **자동 아카이빙**
- 전송 완료된 파일 자동 보관
- 타임스탬프 기반 폴더 구조 (`yyyymmdd_hhmmss`)
- 원본 디렉토리 자동 정리

### 5. **완전한 로깅**
- 모든 작업 과정 상세 로그 기록
- 타임스탬프별 로그 파일 생성
- 디버깅 및 감사 추적 지원

## 시스템 아키텍처
```
┌─────────────────────────────────────────────────────────────┐
│  DICOM 파일 업로드                                            │
│  /dicom/import/#<환자번호>-<환자이름>/                        │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  file_watcher_and_exec.sh                                   │
│  - inotify로 파일 생성 감지                                  │
│  - 180초 디바운스 (마지막 파일 후 3분 대기)                   │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  storescu.sh                                                │
│  1. 메타데이터 수정                                          │
│     - 폴더명에서 환자정보 추출                                │
│     - dcmodify로 Patient ID/Name 업데이트                    │
│  2. PACS 전송                                                │
│     - storescu로 C-STORE 전송                                │
│  3. 아카이빙                                                 │
│     - 처리 완료 파일을 /dicom/archived/로 이동                │
└─────────────────────────────────────────────────────────────┘
```

## 필수 요구사항
- **Docker** (버전 20.10 이상 권장)
- **Docker Compose** (버전 1.29 이상 권장)
- **PACS 서버** (DICOM C-STORE를 지원하는 서버)
- **디스크 공간**: 처리할 DICOM 파일 크기 + 아카이브 공간

## 설치 및 설정

### 1. 저장소 클론
```bash
git clone <repository-url>
cd dicom-importer
```

### 2. 디렉토리 구조 생성
호스트 시스템에 다음 디렉토리들을 생성합니다:
```bash
# Synology NAS 예시 (docker-compose.yml 기본값)
sudo mkdir -p /volume1/docker/dicom_importer
sudo mkdir -p /volume1/dicom_files/import
sudo mkdir -p /volume1/dicom_files/archived
```

또는 다른 경로를 사용하는 경우:
```bash
# 일반 Linux 시스템 예시
sudo mkdir -p /data/dicom_importer
sudo mkdir -p /data/dicom/import
sudo mkdir -p /data/dicom/archived
```

### 3. 스크립트 복사 및 권한 설정
```bash
# 스크립트를 데이터 디렉토리로 복사
cp file_watcher_and_exec.sh /volume1/docker/dicom_importer/
cp storescu.sh /volume1/docker/dicom_importer/
cp entrypoint.sh /volume1/docker/dicom_importer/

# 실행 권한 부여
chmod +x /volume1/docker/dicom_importer/*.sh
```

### 4. PACS 서버 설정
`storescu.sh` 파일을 열어 PACS 서버 정보를 수정합니다:
```bash
vim /volume1/docker/dicom_importer/storescu.sh
```
다음 부분을 환경에 맞게 수정:
```bash
PACS_SERVER_IP="127.0.0.1"      # PACS 서버 IP 주소
PACS_SERVER_PORT="11112"         # PACS 서버 포트
PACS_AET="DCM4CHEE"              # PACS 서버 AET (Application Entity Title)
```

**중요**: Docker 컨테이너에서 호스트의 PACS 서버로 연결하는 경우:
```bash
PACS_SERVER_IP="host.docker.internal"  # Docker Desktop (Windows/Mac)
# 또는
PACS_SERVER_IP="172.17.0.1"            # Linux 호스트
```

### 5. Docker Compose 설정 (선택사항)
다른 경로를 사용하는 경우 `docker-compose.yml`의 볼륨 마운트를 수정:
```yaml
volumes:
  - "/etc/localtime:/etc/localtime:ro"
  - /your/path/dicom_importer:/data
  - /your/path/dicom_files:/dicom
  - /your/path/dicom_importer/entrypoint.sh:/entrypoint.sh
```

### 6. 컨테이너 실행
```bash
docker-compose up -d
```

## 사용 방법
### 기본 사용 흐름
1. **DICOM 파일 준비**
   환자별로 폴더를 생성하고 DICOM 파일을 저장합니다.
   **폴더명 규칙**: `#<환자번호>-<환자이름>`
   예시:
   ```
   /dicom/import/#12345-HongGildong/
   /dicom/import/#67890-KimYoungHee/
   ```

2. **파일 업로드**
   준비된 DICOM 파일들을 `/dicom/import/` 디렉토리로 복사합니다:
   ```bash
   cp -r /source/path/#12345-HongGildong /volume1/dicom_files/import/
   ```

3. **자동 처리 대기**
   - 파일 감시 시스템이 자동으로 새 파일을 감지합니다
   - 마지막 파일 추가 후 **3분 대기** (추가 파일 확인)
   - 3분간 새 파일이 없으면 자동으로 처리 시작

4. **처리 과정**
   시스템이 자동으로 다음 작업을 수행합니다:
   - DICOM 메타데이터 수정 (Patient ID, Patient Name)
   - PACS 서버로 파일 전송
   - 처리된 파일을 아카이브 폴더로 이동

5. **결과 확인**
   ```bash
   # 아카이브 확인
   ls -la /volume1/dicom_files/archived/
   # 로그 확인
   tail -f /volume1/docker/dicom_importer/log/*.log
   ```

### 폴더명 패턴
시스템은 다음 패턴의 폴더명을 인식합니다:
- **정규식**: `^#([0-9]+)-([\#^A-Za-z0-9]+)$`
- **형식**: `#<숫자>-<문자>`
**올바른 예시**:
- `#12345-HongGildong`
- `#00001-Kim#Young^Hee` (DICOM 표준 표기 지원)
- `#99999-TestPatient123`

**잘못된 예시**:
- `12345-HongGildong` (# 누락)
- `#ABC123-Name` (환자번호에 문자 포함)
- `#12345_HongGildong` (구분자가 하이픈이 아님)

## 디렉토리 구조
### 컨테이너 내부 경로
```
/data/
├── file_watcher_and_exec.sh    # 파일 감시 스크립트
├── storescu.sh                 # DICOM 처리 및 전송 스크립트
└── log/
    ├── 20250127-143022.log     # 실행별 로그 파일
    └── log.log                 # 통합 로그 파일
/dicom/
├── import/                     # DICOM 파일 업로드 디렉토리
│   ├── #12345-HongGildong/
│   │   ├── 001.dcm
│   │   └── 002.dcm
│   └── #67890-KimYoungHee/
│       └── study1/
│           └── series1/
│               └── image.dcm
└── archived/                   # 처리 완료 파일 보관
    ├── 20250127_140530/
    │   └── #12345-HongGildong/
    └── 20250127_143022/
        └── #67890-KimYoungHee/
```

### 호스트 시스템 매핑
| 컨테이너 경로 | 호스트 경로 (기본값) | 용도 |
|--------------|---------------------|------|
| `/data` | `/volume1/docker/dicom_importer` | 스크립트 및 로그 |
| `/dicom/import` | `/volume1/dicom_files/import` | DICOM 파일 업로드 |
| `/dicom/archived` | `/volume1/dicom_files/archived` | 처리 완료 파일 |

## 설정 커스터마이징
### 1. 디바운스 시간 변경
파일 추가 후 대기 시간을 변경하려면 `file_watcher_and_exec.sh` 수정:
```bash
DELAY=180  # 기본값: 180초 (3분)
```
예시:
- `DELAY=60`: 1분 대기
- `DELAY=300`: 5분 대기
- `DELAY=600`: 10분 대기

### 2. 타임존 설정
`docker-compose.yml`에서 타임존 수정:
```yaml
environment:
  TZ: "Asia/Seoul"  # 기본값
  # TZ: "America/New_York"
  # TZ: "Europe/London"
```

### 3. PACS 서버 설정
`storescu.sh`에서 다중 PACS 서버 설정 가능:
```bash
# 기본 PACS
PACS_SERVER_IP="192.168.1.100"
PACS_SERVER_PORT="11112"
PACS_AET="MAIN_PACS"

# 백업 PACS (주석 해제 후 사용)
# BACKUP_PACS_IP="192.168.1.200"
# BACKUP_PACS_PORT="11112"
# BACKUP_PACS_AET="BACKUP_PACS"
```

### 4. 로그 보관 정책
로그 파일 크기 제한 또는 자동 삭제를 설정하려면 cron 작업 추가:
```bash
# 30일 이상된 로그 파일 삭제
0 2 * * * find /volume1/docker/dicom_importer/log -name "*.log" -mtime +30 -delete
```

### 5. 아카이브 정책
오래된 아카이브 자동 삭제:
```bash
# 90일 이상된 아카이브 폴더 삭제
0 3 * * * find /volume1/dicom_files/archived -type d -mtime +90 -exec rm -rf {} +
```

## 로그 및 모니터링
### 로그 파일 위치
1. **실행별 로그**: `/data/log/yyyymmdd-HHMMSS.log`
   - 각 스크립트 실행마다 새 로그 파일 생성
   - 처리 내역 추적 용이

2. **통합 로그**: `/data/log/log.log`
   - 모든 실행 내역이 누적됨
   - 장기 모니터링 및 분석용

### 로그 확인 방법
```bash
# 실시간 로그 모니터링
docker logs -f dicom-importer

# 최근 로그 파일 확인
tail -f /volume1/docker/dicom_importer/log/log.log

# 특정 실행 로그 확인
cat /volume1/docker/dicom_importer/log/20250127-143022.log

# 에러만 필터링
grep -i "error\|warn\|fail" /volume1/docker/dicom_importer/log/log.log
```

### 로그 레벨

로그는 다음과 같은 레벨로 분류됩니다:
- `[Watcher]`: 파일 감시 시스템 로그
- `[Waiter]`: 디바운스 대기 프로세스 로그
- `[INFO]`: 일반 정보 메시지
- `[WARN]`: 경고 메시지 (처리는 계속됨)
- `[PHASE 1/2/3]`: 처리 단계별 구분

## 문제 해결
### 1. 파일이 감지되지 않음
**증상**: DICOM 파일을 업로드했지만 처리되지 않음
**해결 방법**:
```bash
# 1. 컨테이너 상태 확인
docker ps | grep dicom-importer

# 2. 컨테이너 로그 확인
docker logs dicom-importer

# 3. inotify 동작 확인
docker exec -it dicom-importer bash
ps aux | grep inotify

# 4. 파일 시스템 권한 확인
ls -la /dicom/import/
```

### 2. PACS 전송 실패
**증상**: 메타데이터는 수정되지만 전송이 안됨
**해결 방법**:
```bash
# 1. 네트워크 연결 확인
docker exec -it dicom-importer ping <PACS_SERVER_IP>

# 2. 포트 확인
docker exec -it dicom-importer nc -zv <PACS_SERVER_IP> <PACS_PORT>

# 3. PACS AET 확인
# PACS 서버 설정에서 허용된 AET 목록 확인

# 4. 수동 전송 테스트
docker exec -it dicom-importer \
  storescu -c DCM4CHEE@<IP>:<PORT> /dicom/import/#12345-Test/
```

**일반적인 원인**:
- PACS 서버 IP/포트 오류
- 방화벽 차단
- PACS 서버에 AET 미등록
- DICOM 네트워크 설정 불일치

### 3. 메타데이터 수정 실패
**증상**: `[WARN] Not a DICOM file` 메시지
**해결 방법**:
```bash
# 1. DICOM 파일 유효성 검사
docker exec -it dicom-importer dcmdump <파일경로>

# 2. DICM 헤더 확인
head -c 132 <파일경로> | tail -c 4
# 출력이 "DICM"이어야 함

# 3. 파일 형식 확인
file <파일경로>
```

### 4. 폴더명 패턴 불일치
**증상**: `[WARN] Folder name pattern does not match`
**해결 방법**:
```bash
# 올바른 형식 확인
# 정규식: ^#([0-9]+)-([\#^A-Za-z0-9]+)$

# 예시:
mv "12345-HongGildong" "#12345-HongGildong"  # # 추가
mv "#ABC-Name" "#123-Name"                   # 환자번호 숫자로 변경
mv "#123_Name" "#123-Name"                   # 구분자 수정
```

### 5. 디스크 공간 부족
**증상**: 아카이빙 중 오류 발생
**해결 방법**:
```bash
# 1. 디스크 사용량 확인
df -h /volume1/dicom_files

# 2. 오래된 아카이브 삭제
find /volume1/dicom_files/archived -type d -mtime +30 -exec rm -rf {} +

# 3. 로그 파일 정리
find /volume1/docker/dicom_importer/log -name "*.log" -mtime +7 -delete
```

### 6. 컨테이너 재시작 반복
**증상**: 컨테이너가 계속 재시작됨
**해결 방법**:
```bash
# 1. 상세 로그 확인
docker logs --tail 100 dicom-importer

# 2. entrypoint.sh 실행 권한 확인
ls -la /volume1/docker/dicom_importer/entrypoint.sh
chmod +x /volume1/docker/dicom_importer/entrypoint.sh

# 3. 스크립트 문법 오류 확인
docker exec -it dicom-importer bash -n /data/file_watcher_and_exec.sh
docker exec -it dicom-importer bash -n /data/storescu.sh
```

### 7. 디바운스 시간 조정 필요
**증상**: 파일이 완전히 업로드되기 전에 처리 시작
**해결 방법**:
`file_watcher_and_exec.sh`에서 `DELAY` 값 증가:
```bash
DELAY=300  # 180초에서 300초(5분)로 증가
```

### 8. 한글 환자명 깨짐
**증상**: 한글 이름이 PACS에서 깨져 보임
**해결 방법**:
```bash
# 1. 컨테이너 로케일 확인
docker exec -it dicom-importer locale

# 2. UTF-8 인코딩 확인
# storescu.sh에서 한글 처리 시 인코딩 명시

# 3. PACS 서버 문자셋 설정 확인
# DICOM 표준 문자셋: ISO_IR 192 (UTF-8)
```

### 로그에서 자주 보이는 메시지
| 메시지 | 의미 | 조치 필요 여부 |
|--------|------|---------------|
| `Lock acquired` | 새 처리 시작 | 정상 |
| `Waiter already active` | 디바운스 타이머 재설정 | 정상 |
| `Timer has been reset` | 새 파일 감지로 대기 연장 | 정상 |
| `Not a DICOM file` | 비DICOM 파일 발견 | 파일 확인 필요 |
| `Pattern does not match` | 폴더명 규칙 불일치 | 폴더명 수정 필요 |
| `Connection refused` | PACS 서버 연결 실패 | 네트워크/설정 확인 |

## 고급 기능
### 1. 여러 PACS 서버로 동시 전송
`storescu.sh`를 수정하여 복수의 PACS 서버로 전송:
```bash
# PHASE 2 수정
echo "[PHASE 2] Executing storescu (DICOM Send)..."

# 주 PACS 전송
storescu -c ${PACS_AET}@${PACS_SERVER_IP}:${PACS_SERVER_PORT} ${DICOM_DIR}

# 백업 PACS 전송
storescu -c ${BACKUP_AET}@${BACKUP_IP}:${BACKUP_PORT} ${DICOM_DIR}

echo "[PHASE 2] All storescu executions completed."
```

### 2. 전송 전 검증 단계 추가
DICOM 파일 무결성 검증 추가:
```bash
# storescu.sh의 PHASE 1과 2 사이에 추가
echo "[PHASE 1.5] Validating DICOM files..."
for folder in "$DICOM_DIR"/*; do
    if [ -d "$folder" ]; then
        find "$folder" -type f | while read file; do
            dcmftest "$file" || echo "[ERROR] Invalid DICOM: $file"
        done
    fi
done

echo "[PHASE 1.5] Validation completed."
```
 
## 라이선스
이 프로젝트는 오픈소스 도구들을 활용합니다:
- **dcm4che**: Apache License 2.0
- **DCMTK**: BSD-style license
- **inotify-tools**: GPL v2

## 기여
버그 리포트, 기능 제안, Pull Request를 환영합니다.

## 지원
문제가 발생하거나 질문이 있으시면 Issue를 등록해주세요.

---

**참고 문서**:
- [DICOM 표준](https://www.dicomstandard.org/)
- [dcm4che 문서](https://www.dcm4che.org/)

- [DCMTK 문서](https://dicom.offis.de/dcmtk)

 
