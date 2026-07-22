# Object storage cho Trino

Tài liệu này gộp phần tổng quan và hướng dẫn cấu hình native file system cho Amazon S3/S3-compatible storage, Azure Storage và Google Cloud Storage. Các connector Hive, Iceberg và Delta Lake đều đọc/ghi file trực tiếp qua các file system này.

Mỗi catalog chỉ chọn **một** cơ chế file system. Vì vậy, hãy bật đúng property theo backend trong catalog cần dùng, chọn đúng một cơ chế xác thực khi các lựa chọn loại trừ nhau, rồi kiểm thử quyền của identity thực tế.

---

## Object storage cho Trino

> Tóm tắt theo [Object storage — Trino current](https://trino.io/docs/current/object-storage.html) (đối chiếu Trino 482 ngày 2026-07-14).

Object storage là lớp lưu các object/tệp của data lake hoặc lakehouse. Các connector Delta Lake, Hive, Hudi và Iceberg dùng Trino để truy cập trực tiếp data files và metadata files trên storage; metadata catalog của connector (như HMS, Glue, REST catalog) vẫn là một thành phần riêng.

### 1. Phạm vi và nguyên tắc cấu hình

Trino có native file-system implementation cho Azure Storage, Google Cloud Storage (GCS) và S3. Native implementation được dùng trong catalog của Delta Lake, Hive, Hudi hoặc Iceberg và phải được bật riêng trong **catalog properties file**.

Mỗi catalog chỉ dùng **một** file-system support. Vì vậy phải chọn một trong ba property sau cho catalog đó, không bật đồng thời chúng:

| Storage | Property bật native support | Mặc định |
| --- | --- | --- |
| Azure Storage | `fs.azure.enabled` | `false` |
| Google Cloud Storage | `fs.gcs.enabled` | `false` |
| S3 hoặc S3-compatible | `fs.s3.enabled` | `false` |

Ví dụ, thêm property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, khi catalog đó truy cập S3.

```properties
fs.s3.enabled=true
```

Không dùng `fs.hadoop.enabled` hoặc các property cũ `hive.s3.*`, `hive.gcs.*`, `hive.azure.*` cho object storage. Legacy object-storage support đã bị gỡ bỏ; `fs.hadoop.enabled` chỉ dành cho HDFS.

### 2. Các lớp quyền cần đồng thời đúng

Một truy vấn chỉ thành công khi tất cả các lớp sau cho phép:

1. Trino authentication và access control cho user/query.
2. Quyền metadata catalog của connector, nếu connector dùng metadata catalog.
3. Credential và IAM/RBAC policy của object storage cho Trino/node/user đang chạy query.
4. Network, DNS, TLS và endpoint giữa coordinator/worker với storage.

Quyền storage không thay thế policy Trino và ngược lại. Dùng least privilege, không lưu access key/secret/OAuth secret/JSON service-account key trong Git.

### 3. Chọn tài liệu theo backend

- [S3 và S3-compatible](#s3-và-s3-compatible-storage-cho-trino): AWS S3, MinIO và endpoint tương thích S3; gồm IAM role, SSE và security mapping.
- [Azure Storage](#azure-storage-cho-trino): Azure Data Lake Storage Gen2, managed identity, access key và OAuth 2.0.
- [Google Cloud Storage](#google-cloud-storage-cho-trino): service account, Application Default Credentials và retry tuning.

### 4. Kiểm thử chung

Sau khi deploy hoặc reload catalog theo quy trình vận hành của bạn, chạy `SHOW SCHEMAS`, `SHOW TABLES` và `SELECT` trên một bảng đại diện. Với catalog có quyền ghi, tạo/ghi/xóa một bảng thử nghiệm để kiểm tra cả metadata catalog lẫn storage permissions.

- [ ] Mỗi catalog chỉ bật đúng một native file-system support.
- [ ] Mọi worker, không chỉ coordinator, có network access và credential cần thiết.
- [ ] Storage URI, metadata catalog và connector dùng cùng convention/region/endpoint phù hợp.
- [ ] Credential/role có least privilege và không tồn tại trong file tracked.
- [ ] Đã kiểm thử read, write, retry/error handling và access denied với identity thực tế.

---

## S3 và S3-compatible storage cho Trino

> Tóm tắt theo [S3 file system support — Trino current](https://trino.io/docs/current/object-storage/file-system-s3.html) (đối chiếu Trino 482 ngày 2026-07-14).

Trino có native implementation cho Amazon S3 và các storage tương thích S3 trong catalog Delta Lake, Hive, Hudi và Iceberg. AWS S3 và MinIO là hai hệ thống được Trino kiểm thử tương thích; với S3-compatible storage khác, cần tự kiểm thử và tham khảo nhà cung cấp.

### 1. Yêu cầu và cách bật native S3

Coordinator và mọi worker cần truy cập được S3 endpoint, có credential/IAM role cần thiết, và dùng connector có hỗ trợ object storage. Metadata catalog của Iceberg/Hive/Delta vẫn phải được cấu hình riêng.

Thêm property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, để bật native S3 support.

```properties
fs.s3.enabled=true
```

Không dùng `fs.hadoop.enabled` cho S3. Các property `hive.s3.*` thuộc legacy implementation đã bị gỡ bỏ; di trú chúng sang native `s3.*` properties.

### 2. Property S3 quan trọng

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `s3.endpoint` | Không đặt | URL endpoint S3; cần cho endpoint tùy chỉnh/S3-compatible. |
| `s3.region` | Không đặt | Region S3 dùng để giao tiếp. |
| `s3.cross-region-access` | `false` | Cho phép cross-region access. |
| `s3.path-style-access` | Không đặt | Dùng path-style cho mọi request; thường cần kiểm tra với S3-compatible endpoint. |
| `s3.storage-class` | `STANDARD` | Storage class khi ghi; ví dụ `STANDARD_IA`, `INTELLIGENT_TIERING`, `GLACIER`. |
| `s3.canned-acl` | `NONE` | Canned ACL khi upload; `NONE` có tác dụng như `PRIVATE`. |
| `s3.sse.type` | `NONE` | Server-side encryption: `S3`, `KMS` hoặc `CUSTOMER`. AWS S3 tự dùng SSE nên `NONE` và `S3` tương đương trên AWS, nhưng S3-compatible có thể khác. |
| `s3.sse.kms-key-id` | Không đặt | KMS key khi `s3.sse.type=KMS`. |
| `s3.sse.customer-key` | Không đặt | AES-256 base64 key khi dùng SSE-C (`CUSTOMER`). |
| `s3.streaming.part-size` | `32MB` | Kích thước part upload streaming; hợp lệ từ `5MB` đến `256MB`. |
| `s3.requester-pays` | `false` | Chuyển chi phí data transfer sang requester. |
| `s3.max-connections` | `500` | Số connection tối đa đến S3. |
| `s3.retry-mode` | `LEGACY` | Retry mode AWS SDK: `LEGACY`, `STANDARD`, `ADAPTIVE`. |
| `s3.max-error-retries` | `20` | Số retry lỗi tối đa. |
| `s3.application-id` | `Trino` | Giá trị thêm vào `User-Agent`. |

Các property network/tuning khác gồm `s3.connection-ttl`, `s3.connection-max-idle-time`, `s3.socket-connect-timeout`, `s3.socket-timeout`, `s3.tcp-keep-alive`, `s3.http-proxy` và nhóm `s3.http-proxy.*`. Chỉ thay đổi sau khi đo lỗi timeout/rate limit/connection pool; tăng connection hoặc retry không thay thế việc kiểm tra S3 throttling, region và network path.

### 3. Authentication

Trino hỗ trợ AWS access/secret key, STS và IAM role. Dùng role/instance profile/web identity thay static key khi môi trường cho phép.

| Property name | Ý nghĩa |
| --- | --- |
| `s3.aws-access-key` / `s3.aws-secret-key` | Static credential; không ghi vào Git. |
| `s3.sts.endpoint` / `s3.sts.region` | Endpoint và region của AWS STS. |
| `s3.iam-role` | ARN role Trino sẽ assume. |
| `s3.role-session-name` | Tên role session; mặc định `trino-filesystem`. |
| `s3.external-id` | External ID cho IAM role trust policy. |
| `s3.use-web-identity-token-credentials-provider` | Chỉ dùng web identity provider, hữu ích với EKS IRSA; mặc định `false`. |

Nếu dùng KMS, role còn cần quyền KMS tương ứng. `s3.sse.customer-key` và static key là secret đặc biệt nhạy cảm; quản lý ngoài catalog file tracked.

### 4. Security mapping theo user, group và S3 prefix

S3 security mapping cho phép chọn credential/IAM role riêng theo Trino user, group hoặc S3 URL prefix. Một mapping có thể có `user`, `group`, `prefix`; nếu có nhiều điều kiện, tất cả phải khớp. Mapping được đánh giá theo thứ tự từ trên xuống: rule cụ thể phải đứng trước rule rộng. Nếu không có rule khớp và không có default mapping, truy cập bị từ chối.

Thêm các property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, để bật mapping từ file JSON.

```properties
s3.security-mapping.enabled=true
s3.security-mapping.config-file=etc/catalog/s3-security-mapping.json
```

Tạo `etc/catalog/s3-security-mapping.json` và đặt nội dung sau vào đó. Đây là ví dụ role-based; thay ARN bằng role đã được cấp quyền và kiểm soát ai được vào group đó.

```json
{
  "mappings": [
    {
      "group": "finance",
      "iamRole": "arn:aws:iam::123456789101:role/finance_users"
    },
    {
      "iamRole": "arn:aws:iam::123456789101:role/default"
    }
  ]
}
```

Mapping entry có thể đặt `accessKey`/`secretKey`, `iamRole`, `roleSessionName`, `allowedIamRoles`, `kmsKeyId`, `allowedKmsKeyIds`, `sseCustomerKey`, `allowedSseCustomerKey`, `endpoint` và `region`. Default mapping có thể dùng `useClusterDefault: true`, nhưng không được kết hợp với setting khác trong chính entry đó.

Các property mapping bổ sung gồm `s3.security-mapping.config-uri`, `s3.security-mapping.json-pointer`, các property `*-credential-name`, `s3.security-mapping.refresh-period` và `s3.security-mapping.colon-replacement`. Chỉ cho phép extra credential role/KMS/SSE-C trong danh sách allowlist rõ ràng.

### 5. Migration, hiệu năng và kiểm thử

Khi di trú legacy config, thay `hive.s3.aws-access-key`, `hive.s3.aws-secret-key`, `hive.s3.iam-role`, `hive.s3.endpoint`, `hive.s3.region` bằng các property native tương ứng `s3.*`; `s3.endpoint` phải là URL hợp lệ gồm `https://` khi cần. Bỏ `fs.hadoop.enabled` nếu chỉ được dùng cho legacy S3.

Để kiểm thử, dùng bảng thử nghiệm trong bucket/prefix có quyền hạn hẹp. Xác minh read, write, list/metadata, encryption, IAM role assumption và failure khi user truy cập prefix không được cấp.

- [ ] `fs.s3.enabled=true` nằm trong đúng catalog và không bật một backend khác trong catalog đó.
- [ ] Endpoint/region/path-style đã được kiểm tra với S3-compatible provider.
- [ ] Static key, KMS key và SSE-C key không tồn tại trong Git/log.
- [ ] IAM policy có quyền S3/KMS tối thiểu, áp dụng đúng bucket/prefix.
- [ ] Security mapping sắp xếp specific-before-general và có default rõ ràng nếu cần.
- [ ] Đã thử read/write, retry/throttling và access denied từ mọi worker.

---

## Azure Storage cho Trino

> Tóm tắt theo [Azure Storage file system support — Trino current](https://trino.io/docs/current/object-storage/file-system-azure.html) (đối chiếu Trino 482 ngày 2026-07-14).

Trino có native implementation để truy cập Azure Data Lake Storage Gen2 (ADLS Gen2) từ catalog Delta Lake, Hive, Hudi hoặc Iceberg. Storage account phải bật **hierarchical namespace**; Azure Blob Storage không có hierarchical namespace không đáp ứng yêu cầu của implementation này.

### 1. Yêu cầu và cách bật Azure Storage

Coordinator và mọi worker phải truy cập được Azure endpoint và có identity được cấp quyền Azure RBAC phù hợp. Metadata catalog của connector được cấu hình riêng với Azure storage.

Thêm các property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, khi dùng default authentication hoặc user-assigned managed identity.

```properties
fs.azure.enabled=true
azure.auth-type=DEFAULT
```

`fs.azure.enabled` mặc định `false` và phải là `true` trước khi các property `azure.*` có hiệu lực. Không dùng `fs.hadoop.enabled` hoặc `hive.azure.*` cho Azure object storage; legacy implementation đã bị gỡ bỏ.

### 2. Property chung và tuning

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `fs.azure.enabled` | `false` | Bật native Azure Storage implementation. |
| `azure.auth-type` | `DEFAULT` | Chọn `DEFAULT`, `ACCESS_KEY` hoặc `OAUTH`. |
| `azure.endpoint` | `core.windows.net` | Hostname suffix Azure endpoint. Dùng suffix cloud tương ứng cho US Government, Germany hoặc China cloud. |
| `azure.read-block-size` | `4MB` | Kích thước block đọc. |
| `azure.write-block-size` | `4MB` | Kích thước block ghi. |
| `azure.max-write-concurrency` | `8` | Số thao tác ghi đồng thời tối đa. |
| `azure.max-single-upload-size` | `4MB` | Kích thước upload đơn tối đa. |
| `azure.max-http-requests` | 2 × số CPU mỗi node | Số HTTP request Azure đồng thời mỗi node; giảm khi gặp rate limit. |
| `azure.connection-pool-max-idle-time` | `5m` | Thời gian connection idle trước khi pool đóng. |
| `azure.http-request-timeout` | `10m` | Timeout HTTP, gồm thời gian Azure SDK retry. |
| `azure.application-id` | `Trino` | Giá trị thêm vào header `User-Agent`. |
| `azure.multipart-write-enabled` | `false` | Bật multipart write cho file lớn. |

Không tăng concurrency/block size chỉ để xử lý lỗi. Trước tiên kiểm tra Azure throttling, băng thông, file size, số worker và permission; sau đó thay đổi từng property và đo workload đại diện.

### 3. Chọn một cơ chế authentication

`azure.auth-type` quyết định authentication. `DEFAULT`, `ACCESS_KEY` và `OAUTH` là lựa chọn thay thế nhau; không trộn property secret từ phương án này vào phương án khác.

#### 3.1 DEFAULT và user-assigned managed identity

`DEFAULT` nạp credential từ environment nếu có hoặc dùng user-assigned managed identity. Khi chọn user-assigned identity, thêm property phù hợp vào catalog properties file đang dùng; chỉ được đặt **một** trong hai property identity sau.

```properties
azure.user-assigned-managed-identity.client-id=<client-id>
```

Hoặc thêm property sau vào cùng catalog properties file để định danh identity bằng resource ID.

```properties
azure.user-assigned-managed-identity.resource-id=<resource-id>
```

Đừng đặt cả `client-id` lẫn `resource-id`. Managed identity thường là lựa chọn nên ưu tiên vì không phải lưu long-lived secret trong catalog.

#### 3.2 Access key

Với access key, đặt `azure.auth-type=ACCESS_KEY` và cung cấp `azure.access-key` từ secret management an toàn. `azure.access-key` là decrypted access key của storage account; không đưa nó vào file tracked hoặc Markdown chia sẻ công khai. Access key cấp quyền rộng ở mức account nên cần xoay vòng và hạn chế tối đa.

#### 3.3 OAuth 2.0 service principal

Với service principal, đặt `azure.auth-type=OAUTH`. Các property cần có là:

| Property name | Ý nghĩa |
| --- | --- |
| `azure.oauth.tenant-id` | Tenant ID Azure dùng để xác thực. |
| `azure.oauth.endpoint` | URL endpoint OAuth 2.0. |
| `azure.oauth.client-id` | Client/application ID của service principal. |
| `azure.oauth.secret` | Client secret; phải quản lý ngoài Git. |

OAuth service principal phù hợp khi một catalog cần truy cập nhiều storage account. Cấp Azure RBAC role theo từng storage account/container, ví dụ quyền Blob Data phù hợp, thay vì cấp rộng theo subscription.

### 4. Authorization, vận hành và migration

Azure RBAC/storage ACL quyết định Trino identity có thể đọc/ghi object nào; system access control của Trino quyết định user Trino nào có thể dùng catalog/table. Cấu hình cả hai, áp dụng least privilege và kiểm thử bằng user/role thực tế.

Khi di trú từ legacy Azure support: bật `fs.azure.enabled=true`, bỏ `fs.hadoop.enabled` nếu chỉ dùng cho Azure, chọn `azure.auth-type`, rồi đổi `hive.azure.abfs-access-key` thành `azure.access-key`; đổi nhóm `hive.azure.abfs.oauth.*` sang `azure.oauth.*`. Các property legacy `hive.azure.abfs-storage-account`, `hive.azure.wasb-access-key` và `hive.azure.wasb-storage-account` phải bị loại bỏ.

Sau khi deploy catalog, thử đọc bảng hiện có, rồi trong location thử nghiệm tạo/ghi/xóa bảng để xác minh quyền đọc, ghi, rename/delete metadata và retry behavior.

- [ ] Storage account là ADLS Gen2 và đã bật hierarchical namespace.
- [ ] `fs.azure.enabled=true` nằm trong đúng catalog, không bật backend khác trong catalog đó.
- [ ] Mọi worker có network access và cùng cơ chế identity/credential cần thiết.
- [ ] Chọn đúng một auth type; không đặt đồng thời client ID và resource ID cho managed identity.
- [ ] Access key/OAuth secret không nằm trong Git hoặc log.
- [ ] Azure RBAC/ACL và policy Trino đều cấp least privilege.
- [ ] Đã kiểm thử read/write và xử lý rate limit/timeout trong môi trường thử nghiệm.

---

## Google Cloud Storage cho Trino

> Tóm tắt theo [Google Cloud Storage file system support — Trino current](https://trino.io/docs/current/object-storage/file-system-gcs.html) (đối chiếu Trino 482 ngày 2026-07-14).

Trino có native implementation để truy cập Google Cloud Storage (GCS) từ catalog Delta Lake, Hive, Hudi hoặc Iceberg. GCS authentication, retry và endpoint được cấu hình trong catalog properties file của connector đang dùng; metadata catalog của connector vẫn là cấu hình riêng.

### 1. Cách bật native GCS

Coordinator và toàn bộ worker cần truy cập được GCS endpoint và có Google Cloud credential/permission phù hợp. Thêm property sau vào catalog properties file đang dùng, chẳng hạn `etc/catalog/iceberg.properties`, để bật native GCS support.

```properties
fs.gcs.enabled=true
```

`fs.gcs.enabled` mặc định `false`. Không dùng `fs.hadoop.enabled` hoặc `hive.gcs.*` để truy cập GCS vì legacy implementation đã bị gỡ bỏ.

### 2. Property chung và retry

| Property name | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `fs.gcs.enabled` | `false` | Bật native GCS implementation. |
| `gcs.project-id` | Không đặt | Identifier của Google Cloud project. |
| `gcs.endpoint` | GCS endpoint mặc định | URL endpoint tùy chọn, ví dụ custom GCS-compatible endpoint. |
| `gcs.client.max-retries` | `20` | Số lần thử RPC tối đa. |
| `gcs.client.backoff-scale-factor` | `3` | Hệ số scale cho retry delay. |
| `gcs.client.max-retry-time` | `25s` | Tổng thời gian tối đa cho RPC retry. |
| `gcs.client.min-backoff-delay` | `10ms` | Backoff nhỏ nhất giữa các retry. |
| `gcs.client.max-backoff-delay` | `2s` | Backoff lớn nhất giữa các retry. |
| `gcs.read-block-size` | `2MiB` | Kích thước block tối thiểu đọc mỗi RPC. |
| `gcs.write-block-size` | `16MiB` | Kích thước block tối thiểu ghi mỗi RPC. |
| `gcs.page-size` | `100` | Số blob tối đa mỗi page. |
| `gcs.batch-size` | `100` | Số blob xóa mỗi batch; phù hợp với khuyến nghị GCS. |
| `gcs.application-id` | `Trino` | Giá trị thêm vào header `User-Agent`. |

Tuning retry/backoff chỉ sau khi xác minh IAM, endpoint, quota, network và đặc tính workload. Retry lớn có thể làm query chờ lâu hơn khi permission hoặc cấu hình endpoint vốn sai.

### 3. Authentication

`gcs.auth-type` mặc định là `SERVICE_ACCOUNT` và có ba lựa chọn:

| Giá trị | Hành vi |
| --- | --- |
| `SERVICE_ACCOUNT` | Nạp credential từ environment. Có thể ghi đè bằng `gcs.json-key` hoặc `gcs.json-key-file-path`. |
| `ACCESS_TOKEN` | Dùng OAuth 2.0 token do client cung cấp để truy cập GCS. |
| `APPLICATION_DEFAULT` | Tìm Application Default Credentials (ADC) trong environment; nếu không có ADC, filesystem dùng unauthenticated credential một cách tường minh. |

`gcs.json-key` chứa service-account key dưới dạng JSON; `gcs.json-key-file-path` là path đến JSON key file trên **mỗi node**. Hai property này loại trừ nhau. Ưu tiên workload identity/ADC khi hạ tầng hỗ trợ; nếu dùng key file, bảo vệ file ngoài Git, giới hạn quyền đọc và xoay vòng key.

Thêm property sau vào catalog properties file đang dùng chỉ khi cần định danh project rõ ràng.

```properties
gcs.project-id=<project-id>
```

Không đặt JSON service-account key trực tiếp vào catalog file tracked. Quyền IAM GCS của service account/workload identity phải tối thiểu theo bucket/prefix và thao tác read/write thực tế.

### 4. Migration, security và kiểm thử

Khi di trú từ legacy GCS support, bật `fs.gcs.enabled=true`, bỏ `fs.hadoop.enabled` nếu chỉ được dùng cho legacy GCS, đổi `hive.gcs.json-key-file-path` thành `gcs.json-key-file-path`. Với legacy `hive.gcs.use-access-token`, chọn giá trị `gcs.auth-type` phù hợp (thường là `ACCESS_TOKEN`).

GCS IAM quyết định identity storage có thể làm gì; system access control của Trino quyết định user Trino nào có thể truy cập catalog/table. Cấu hình cả hai lớp và kiểm thử access denied, không chỉ happy path.

Sau khi deploy catalog, đọc một bảng trong bucket thật và thực hiện create/write/drop trên location thử nghiệm. Xác minh credential được nhận trên toàn bộ worker, không chỉ coordinator.

- [ ] `fs.gcs.enabled=true` nằm trong đúng catalog và catalog không bật backend khác.
- [ ] Mọi worker có network access tới endpoint và Google credential có hiệu lực.
- [ ] Chọn đúng `gcs.auth-type`; không đặt cả `gcs.json-key` và `gcs.json-key-file-path`.
- [ ] Service-account key/token không nằm trong Git/log; ưu tiên ADC/workload identity khi có thể.
- [ ] GCS IAM và Trino access control đều least privilege.
- [ ] Đã kiểm thử read/write, retry/quota failure, endpoint tùy chỉnh (nếu dùng) và access denied.

## References

- [Trino — Object storage](https://trino.io/docs/current/object-storage.html)
- [Trino — Metastores](https://trino.io/docs/current/object-storage/metastores.html)
- [Trino — File system cache](https://trino.io/docs/current/object-storage/file-system-cache.html)
- [Trino — S3 file system support](https://trino.io/docs/current/object-storage/file-system-s3.html)
- [Trino — S3 migration](https://trino.io/docs/current/object-storage/file-system-s3.html#migration-from-legacy-s3-file-system)
- [Trino — Azure Storage file system support](https://trino.io/docs/current/object-storage/file-system-azure.html)
- [Trino — Azure migration](https://trino.io/docs/current/object-storage/file-system-azure.html#migration-from-legacy-azure-storage-file-system)
- [Trino — Google Cloud Storage file system support](https://trino.io/docs/current/object-storage/file-system-gcs.html)
- [Trino — GCS migration](https://trino.io/docs/current/object-storage/file-system-gcs.html#migration-from-legacy-google-cloud-storage-file-system)

