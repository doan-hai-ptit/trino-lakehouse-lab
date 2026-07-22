# Bảo mật Trino

Tài liệu này gộp các thành phần bảo mật của Trino theo thứ tự triển khai: bảo vệ client access, bảo vệ giao tiếp giữa các node, xác thực, chuẩn hóa danh tính, phân quyền và quản lý secret. Các cơ chế này bổ sung nhau: TLS không thay authentication, authentication không thay authorization, và policy Trino không thay quyền ở data source.

Hãy triển khai từng lớp, restart và kiểm thử trước khi sang lớp tiếp theo. Mỗi phần dưới đây nêu rõ lý do dùng cơ chế đó, vị trí cấu hình và các bước kiểm thử.

---

## Tổng quan bảo mật Trino

> Tóm tắt theo [Security overview — Trino current](https://trino.io/docs/current/security/overview.html) (đối chiếu Trino 483 ngày 2026-07-21).

Cài đặt Trino mặc định không bật các tính năng bảo mật. Khi vận hành cluster, cần bảo vệ đồng thời ba bề mặt: client truy cập coordinator, giao tiếp bên trong cluster và Trino truy cập data source. Ba lớp này bổ sung cho nhau; TLS không thay authentication, authentication không thay authorization, và policy Trino không thay quyền tại data source.

### 1. Phạm vi bảo mật

| Bề mặt | Mục tiêu | Cơ chế chính |
| --- | --- | --- |
| Client → coordinator | Bảo vệ traffic và xác định/giới hạn người dùng. | TLS/HTTPS, authentication, user/group mapping, system access control. |
| Coordinator ↔ worker | Chỉ node hợp lệ tham gia cluster; tùy chọn mã hóa traffic nội bộ. | Shared secret, internal TLS. |
| Trino → data source | Connector chỉ dùng credential và kết nối phù hợp với source. | TLS, credential/identity của connector, secrets management, IAM/RBAC hoặc quyền của database. |

Coordinator là điểm quản lý mọi client access. Vì vậy, không chỉ bảo vệ endpoint công khai: phải bảo đảm client không thể truy cập trực tiếp một endpoint coordinator không được TLS hoặc proxy bảo vệ.

### 2. Thứ tự cấu hình khuyến nghị

Trino khuyến nghị cấu hình từng bước, restart server và kiểm tra kết quả sau mỗi bước trước khi làm bước kế tiếp:

1. Bật TLS/HTTPS cho client access. Ưu tiên load balancer hoặc proxy kết thúc HTTPS khi kiến trúc cho phép, và dùng certificate được client tin cậy.
2. Cấu hình shared secret giống hệt nhau trên mọi node.
3. Bật authentication. Password file là điểm bắt đầu đơn giản để kiểm tra luồng đăng nhập; sau đó có thể chuyển sang LDAP, OAuth 2.0, certificate, JWT, Salesforce hoặc Kerberos theo nhu cầu.
4. Bật authorization/access control. File-based rules phù hợp để bắt đầu, sau đó có thể dùng Open Policy Agent (OPA), Apache Ranger hoặc implementation tùy chỉnh.

Không gộp nhiều thay đổi bảo mật vào một lần deploy. Khi lỗi xảy ra, việc tách bước giúp xác định rõ lớp TLS, authentication, mapping hay policy nào gây ra lỗi.

### 3. Bảo vệ client access

#### Encryption

Trino dùng HTTPS với TLS để bảo vệ tính toàn vẹn và bí mật của traffic client → server khi truyền. HTTPS chỉ là lớp transport: user vẫn cần authentication, và user đã xác thực vẫn cần policy authorization.

#### Authentication và user name management

Authentication xác định principal của client. Chọn một provider phù hợp với hệ thống identity hiện có; password-file phù hợp cho bước khởi đầu hoặc môi trường nhỏ, còn LDAP/OAuth/JWT/certificate thường phù hợp hơn khi đã có identity provider trung tâm.

Sau authentication, user mapping có thể đổi username phức tạp từ identity provider thành username Trino chuẩn hóa, ví dụ `alice@example.com` thành `alice`. Group mapping gán user vào group để các policy dùng group thay vì lặp từng username. Password file kiểm tra username đầu vào trước khi user mapping được áp dụng, nên entry password và policy sau mapping có thể cần dùng hai tên khác nhau.

#### Authorization và access control

Authentication thành công không tự tạo ra least privilege. Theo mặc định, access control của Trino cho phép mọi operation đối với mọi user đã xác thực. Phải cấu hình system access control để giới hạn quyền catalog, schema, table, column, function, query hoặc hành động quản trị theo policy mong muốn.

Các lựa chọn chính là file-based access control với JSON rules, OPA, Ranger hoặc plugin access-control tùy chỉnh. Ranger còn hỗ trợ row filter, column masking tại thời điểm thực thi query và audit log. Với query `SELECT *`, Trino mặc định trả lỗi nếu user không có quyền với bất kỳ column nào được yêu cầu; property toàn cục `hide-inaccessible-columns=true` thay đổi hành vi này thành ẩn các column không được phép.

### 4. Bảo vệ giao tiếp nội bộ và secret

Shared secret xác thực communication giữa coordinator và worker. Nó bắt buộc khi dùng bất kỳ client authentication nào hoặc khi bật internal TLS; giá trị phải giống nhau trên tất cả node. Internal TLS thêm mã hóa traffic node-to-node, nhưng không thay HTTPS cho client access.

Password, access key và các giá trị nhạy cảm trong `config.properties` hoặc catalog properties file không nên được commit. Trino hỗ trợ tham chiếu biến môi trường theo cú pháp `${ENV:TEN_BIEN}` cho các properties file. Xem [phần biến môi trường](#dùng-biến-môi-trường-cho-secret-trong-trino) để triển khai và kiểm tra cách này.

### 5. Bảo vệ truy cập data source

Mỗi catalog dùng một connector, và connector quyết định cách Trino kết nối đến data source. Cấu hình bảo mật cần xét riêng cho từng catalog: TLS đến source, credential/role, network reachability và quyền đọc/ghi thực tế của identity đó.

Quyền ở data source không thay thế access control của Trino: quyền source quyết định connector có thể làm gì, còn policy Trino giới hạn user nào được yêu cầu query qua Trino. Cấp quyền tối thiểu ở cả hai lớp, và kiểm tra credential/identity có mặt trên mọi node thực thi query, không chỉ coordinator.

### 6. Kiểm tra sau cấu hình

1. Xác nhận endpoint client chỉ chấp nhận HTTPS và certificate được client tin cậy.
2. Thử một login hợp lệ và một login không hợp lệ; kiểm tra username sau mapping nếu có.
3. Thử query được phép và query bị từ chối trên catalog, schema, table và column quan trọng.
4. Xác nhận số worker `ACTIVE` đúng sau khi đặt shared secret; worker có secret khác không được đăng ký.
5. Với từng catalog, thử read và—nếu ứng dụng cho phép—write vào location/table kiểm thử bằng identity thật.
6. Rà soát log, manifest deploy và Git để bảo đảm secret không bị in hoặc commit.

Checklist:

- [ ] HTTPS/TLS bảo vệ client → coordinator.
- [ ] Authentication được bật và username/group mapping có kiểm thử.
- [ ] System access control áp dụng least privilege; không dựa vào default allow.
- [ ] Shared secret giống nhau trên mọi node và internal TLS được cân nhắc theo threat model.
- [ ] Credential của data source dùng secret manager/biến môi trường hoặc identity ngắn hạn, không nằm trong Git.
- [ ] Quyền Trino và quyền tại data source đều được kiểm thử cho allow/deny cases.

---

## HTTPS cho Trino qua reverse proxy hoặc TLS trực tiếp

> Tóm tắt theo [TLS and HTTPS — Trino current](https://trino.io/docs/current/security/tls.html) (đối chiếu Trino 483 ngày 2026-07-22).

HTTPS bảo vệ traffic **client → coordinator** và là lớp nền tảng cho mọi cơ chế authentication của Trino. Chọn một trong hai cách triển khai: kết thúc TLS tại load balancer/reverse proxy, đây là cách Trino ưu tiên; hoặc bật TLS trực tiếp trên coordinator khi không có proxy phù hợp.

### 1. TLS termination tại load balancer hoặc reverse proxy

Proxy nhận kết nối HTTPS bằng certificate được client tin cậy và chuyển tiếp request đến HTTP endpoint nội bộ của coordinator. Chỉ proxy/load balancer mới được phép truy cập endpoint HTTP đó; nếu client không tin cậy có thể gửi trực tiếp request kèm forwarded header, coordinator có thể coi cleartext traffic là HTTPS.

Với reverse proxy tương thích Nginx, tạo virtual-host configuration tương đương sau và thay certificate path, hostname cùng upstream bằng giá trị của môi trường triển khai:

```nginx
server {
    listen 443 ssl;
    server_name trino.example.com;

    ssl_certificate     /path/to/trino.example.com.pem;
    ssl_certificate_key /path/to/trino.example.com-key.pem;

    location / {
        proxy_pass http://coordinator.internal:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

Forwarded header cho Trino biết TLS đã được proxy xác thực. Thêm property sau vào `etc/config.properties` trên coordinator:

```properties
http-server.process-forwarded=true
```

Không bật `http-server.https.enabled=true` chỉ để dùng TLS termination tại proxy. Giữ `discovery.uri` theo cấu hình giao tiếp nội bộ hiện có; endpoint công khai của client là URL HTTPS của proxy, không phải discovery URI.

### 2. TLS trực tiếp trên coordinator

Dùng TLS trực tiếp khi coordinator là HTTPS endpoint cho client. Certificate file phải được process Trino trên coordinator đọc được và được bảo vệ khỏi sao chép hoặc sửa đổi trái phép. Certificate được CA tin cậy toàn cục hoặc nội bộ thường phù hợp hơn self-signed certificate vì client không phải cài thêm truststore.

Thêm các property sau vào `etc/config.properties` trên coordinator, rồi thay certificate path và HTTPS port theo môi trường triển khai:

```properties
http-server.https.enabled=true
http-server.https.port=8443
http-server.https.keystore.path=etc/clustercoord.pem
```

`http-server.https.keystore.path` hỗ trợ PEM, PKCS#12 và JKS. JKS luôn cần password; PEM có password không được Trino hỗ trợ. Khi dùng JKS, thêm property sau vào `etc/config.properties` trên coordinator:

```properties
http-server.https.keystore.key=<keystore-password>
```

Không bật `http-server.authentication.allow-insecure-over-http=true` để xử lý lỗi client: khi HTTPS và authentication được bật, Trino tự tắt HTTP client access để tránh gửi password trên cleartext.

### 3. Kiểm thử và lỗi thường gặp

Restart coordinator sau mỗi thay đổi. Mở Web UI và chạy CLI bằng HTTPS URL công khai; sau khi authentication được bật, thử cả credential đúng lẫn sai.

Chạy lệnh sau từ client để kiểm thử HTTPS và thực thi query:

```bash
trino --server https://trino.example.com:8443 --user <USER> --password
```

Kiểm tra thêm rằng:

- Certificate có SAN khớp hostname client truy cập và chain được client tin cậy.
- Chỉ load balancer/reverse proxy được truy cập HTTP endpoint coordinator khi TLS kết thúc ở proxy.
- `http-server.process-forwarded=true` chỉ được bật khi đường đi đến coordinator đã được network policy bảo vệ.
- Self-signed certificate chỉ phù hợp cho phát triển nội bộ có client truststore được quản lý; không phù hợp cho production.

### 4. Checklist

- [ ] Chọn đúng một cách: TLS termination tại proxy/load balancer hoặc TLS trực tiếp trên coordinator.
- [ ] Certificate, private key và password keystore không nằm trong Git hay log.
- [ ] Client chỉ dùng HTTPS URL; HTTP endpoint nội bộ không public.
- [ ] Đã kiểm thử Web UI, CLI và một query qua HTTPS.


---

## Secure internal communication cho Trino

> Tóm tắt theo [Secure internal communication — Trino current](https://trino.io/docs/current/security/internal-communication.html) (đối chiếu Trino 483 ngày 2026-07-22).

Cơ chế này xác thực giao tiếp **coordinator ↔ worker** bằng shared secret và tùy chọn mã hóa traffic giữa các node bằng TLS tự động. Nó khác với HTTPS cho client; triển khai độc lập hoặc đồng thời với [HTTPS client access](#https-cho-trino-qua-reverse-proxy-hoặc-tls-trực-tiếp) theo threat model.

### 1. Khi nào shared secret là bắt buộc

Shared secret là bắt buộc khi cluster dùng bất kỳ client authentication nào hoặc khi bật internal TLS. Nó ngăn node không có secret tham gia cluster, nhưng không mã hóa traffic nếu `internal-communication.https.required` chưa được bật.

Tạo một secret dài, ngẫu nhiên trong secret manager của môi trường. Không commit, in vào log hay dùng literal production trong file cấu hình.

Để tạo giá trị thử nghiệm trên Linux, chạy:

```bash
openssl rand 512 | base64 -w 0
```

Thêm property sau vào `etc/config.properties` trên coordinator và **mọi** worker, với cùng một giá trị ở tất cả node:

```properties
internal-communication.shared-secret=<SHARED_SECRET>
```

### 2. Bật internal TLS (tùy chọn)

Internal TLS mã hóa toàn bộ giao tiếp giữa các node. Trino tự tạo certificate và trust configuration; vì vậy `discovery.uri` phải dùng **IP address** của coordinator, không dùng hostname hoặc FQDN. Mọi node phải được cấu hình đồng nhất, nếu không node cấu hình sai sẽ không thể tham gia cluster.

Sau khi cấu hình shared secret, thêm các property sau vào `etc/config.properties` trên coordinator và mọi worker. Thay placeholder bằng IP coordinator và port mà tất cả node đều truy cập được:

```properties
internal-communication.https.required=true
discovery.uri=https://<COORDINATOR_IP>:<HTTPS_PORT>
http-server.https.enabled=true
http-server.https.port=<HTTPS_PORT>
```

Giữ firewall, security group hoặc network policy chỉ cho phép traffic nội bộ cần thiết giữa các node. Internal TLS không thay thế HTTPS cho client; nếu coordinator nhận client traffic trực tiếp, cấu hình TLS client access riêng.

### 3. Triển khai và xác minh

Restart coordinator và tất cả worker sau khi thay đổi `discovery.uri` hoặc internal TLS. Trên Web UI, xác nhận số `ACTIVE WORKERS` bằng số worker có shared secret hợp lệ.

Để kiểm thử có kiểm soát, đổi secret trên một worker thử nghiệm và restart riêng worker đó: worker phải không đăng ký được, khiến số `ACTIVE WORKERS` giảm. Khôi phục secret, restart worker và xác nhận node đăng ký lại. Không dùng cách kiểm thử này trên worker không thể ngắt quãng.

### 4. Hiệu năng và tinh chỉnh

Mã hóa làm tăng chi phí CPU và có thể ảnh hưởng rõ ở distributed join, aggregation, window function hoặc workload chuyển nhiều dữ liệu giữa node. Đo workload thực tế trước và sau khi bật; query ít trao đổi dữ liệu thường bị ảnh hưởng ít hơn.

Internal TLS dùng HTTP/2 mặc định để tăng khả năng mở rộng. Chỉ khi số liệu đo cho thấy cần thiết, thêm property sau vào `etc/config.properties` trên mọi node để tắt nó:

```properties
internal-communication.http2.enabled=false
```

Trên hệ thống băng thông rất cao, entropy có thể trở thành bottleneck. Sau khi đánh giá rủi ro và đo đạc, thêm property sau vào `etc/config.properties` trên mọi node:

```properties
http-server.https.secure-random-algorithm=SHA1PRNG
```

Nếu môi trường thiếu entropy để seed thuật toán trên, thêm JVM option sau vào `etc/jvm.config` trên mọi node:

```text
-Djava.security.egd=file:/dev/urandom
```

### 5. Checklist

- [ ] Shared secret được lấy từ secret manager và giống nhau trên mọi node.
- [ ] Khi bật internal TLS, `discovery.uri` dùng IP coordinator và HTTPS port giống nhau trên mọi node.
- [ ] Tất cả coordinator/worker đã restart và số `ACTIVE WORKERS` đúng.
- [ ] Đã kiểm thử node có secret sai không thể đăng ký, trong phạm vi an toàn.
- [ ] Đã đo ảnh hưởng hiệu năng trước khi áp dụng tuning HTTP/2 hoặc random source.


---

## Xác thực bằng password file cho Trino

> Tóm tắt theo [Password file authentication — Trino current](https://trino.io/docs/current/security/password-file.html) (đối chiếu Trino 483 ngày 2026-07-22).

Password file authentication xác thực username/password của client bằng hash trong một file. Nó là **authentication**, không phải authorization: sau khi user đăng nhập, cần thêm access control (ví dụ [file-based access control](#file-based-access-control-cho-trino)) để giới hạn catalog, schema và table.

### 1. Điều kiện bảo mật

Password authentication yêu cầu HTTPS cho client access và shared secret cho giao tiếp nội bộ cluster. HTTPS ngăn password bị truyền qua cleartext; shared secret xác thực node giữa coordinator và worker. Thiết lập hai lớp này trước khi bật login bằng password.

### 2. Tạo và bảo vệ password file

Đặt password file ở vị trí chỉ process Trino trên coordinator đọc được, ngoài Git và ngoài thư mục cấu hình có thể bị ghi đè khi nâng cấp. Secret manager, secret volume hoặc cơ chế provision bí mật của nền tảng triển khai phù hợp hơn việc lưu hash trong image hay source tree.

Trong password file đã tạo, mỗi dòng gồm username, dấu `:` và password hash. Trino hỗ trợ bcrypt (cost tối thiểu `8`) hoặc PBKDF2; bcrypt là lựa chọn phổ biến:

```text
test:$2y$10$BqTb8hScP5DfcpmHo5PeyugxHz5Ky/qf3wrpD7SNm8sWuA3VlGqsa
```

Trên hệ thống có Apache `htpasswd`, tạo file trống và thêm hoặc cập nhật user bằng bcrypt cost `10`:

```bash
touch password.db
htpasswd -B -C 10 password.db test
```

Không chép password hash hoặc lệnh có password thật vào terminal history, log CI/CD hay tài liệu.

### 3. Cấu hình password authenticator trên coordinator

Tạo `etc/password-authenticator.properties` trên coordinator và đặt nội dung sau vào file đó. Thay path bằng vị trí password file mà process Trino đọc được:

```properties
password-authenticator.name=file
file.password-file=/path/to/password.db
file.refresh-period=5s
```

`file.refresh-period` mặc định là `5s`; có thể bỏ dòng này để dùng mặc định. Reload file cho phép thay đổi password có hiệu lực mà không cần đổi `config.properties`, nhưng vẫn kiểm soát quyền ghi file chặt chẽ.

Thêm property sau vào `etc/config.properties` trên coordinator để bật kiểu xác thực này:

```properties
http-server.authentication.type=PASSWORD
```

### 4. Triển khai và kiểm thử

Đảm bảo password file có quyền đọc cho account chạy Trino trên coordinator và không thể đọc bởi user không cần thiết. Worker không dùng password authenticator file để xác thực client; tuy vậy mọi node vẫn cần shared secret giống nhau.

Sau khi restart coordinator, mở Web UI bằng HTTPS URL và thử một credential hợp lệ lẫn không hợp lệ. Dùng CLI qua HTTPS để kiểm thử luồng client thật:

```bash
trino --server https://trino.example.com:8443 --user test --password
```

Đăng nhập thành công chỉ chứng minh authentication hoạt động. Sau đó thử một query được phép và một query bị từ chối để xác nhận access control vẫn thực thi đúng.

### 5. Checklist

- [ ] HTTPS và shared secret đã hoạt động trước khi bật password authentication.
- [ ] Password file dùng bcrypt/PBKDF2, nằm ngoài Git và được phân quyền đọc tối thiểu.
- [ ] `password-authenticator.properties` chỉ có trên coordinator và path trỏ đúng password file.
- [ ] Đã kiểm thử login đúng/sai qua Web UI hoặc CLI HTTPS.
- [ ] Access control có policy allow/deny riêng; không dựa vào authentication để phân quyền.


---

## Xác thực LDAP cho Trino

> Tóm tắt theo [LDAP authentication — Trino current](https://trino.io/docs/current/security/ldap.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-13).

LDAP authentication xác thực người dùng frontend của Trino (CLI, JDBC và ODBC) với một dịch vụ LDAP bên ngoài. Client gửi username/password cho coordinator; coordinator thực hiện LDAP bind để kiểm tra thông tin đó. Hiện Trino chỉ hỗ trợ cơ chế LDAP simple authentication.

LDAP là **authentication**, không phải authorization cho catalog, schema hay table. Sau khi đăng nhập, dùng system access control phù hợp, chẳng hạn [file-based access control](#file-based-access-control-cho-trino), để giới hạn dữ liệu và thao tác. Nếu username LDAP cần chuẩn hóa trước khi dùng trong rule, xem thêm [user mapping](#user-mapping-cho-trino).

### 1. Điều kiện và phạm vi cấu hình

- Chỉ cấu hình LDAP trên **coordinator**; worker không cần `password-authenticator.properties`.
- Client phải truy cập coordinator qua TLS/HTTPS. LDAP authentication cũng yêu cầu shared secret được cấu hình cho giao tiếp nội bộ của Trino.
- Dùng `ldaps://` và truststore có certificate CA/server phù hợp. `ldap://` không mã hóa chỉ có thể dùng khi chủ động bật `ldap.allow-insecure=true`; không phù hợp cho môi trường production.
- Địa chỉ LDAP, DN, password bind, keystore và truststore là dữ liệu hạ tầng hoặc bí mật. Giữ chúng ngoài Git khi có thể và giới hạn quyền đọc các file chứa chúng.

### 2. Bật password authentication và HTTPS

LDAP là một password authenticator. Trước tiên hãy cấu hình TLS/HTTPS cho coordinator theo tài liệu TLS của Trino, rồi bật kiểu xác thực `PASSWORD`.

Thêm property sau vào `etc/config.properties` trên coordinator.

```properties
http-server.authentication.type=PASSWORD
```

`PASSWORD` cũng được dùng bởi password-file và Salesforce authentication. Password authenticator được cấu hình riêng trên coordinator.

#### User mapping tùy chọn

Sau khi LDAP xác thực thành công, Trino có thể map username thành tên chuẩn dùng trong Trino. Chọn **một** trong hai cách: `http-server.authentication.password.user-mapping.pattern` hoặc `http-server.authentication.password.user-mapping.file`; không đặt đồng thời cả hai. Nếu pattern/rule không khớp, đăng nhập bị từ chối. Mặc định khi không cấu hình mapping là `(.*)`.

Thêm property sau vào `etc/config.properties` trên coordinator khi mọi username có cùng định dạng và cần lấy capture group đầu tiên làm Trino username.

```properties
http-server.authentication.password.user-mapping.pattern=(.*)(@.*)
```

Nếu cần nhiều rule hoặc ngoại lệ, tạo `etc/user-mapping.json` theo [phần user mapping](#user-mapping-cho-trino), rồi thêm `http-server.authentication.password.user-mapping.file=etc/user-mapping.json` vào `etc/config.properties` trên coordinator thay cho pattern.

### 3. Cấu hình LDAP password authenticator

Tạo `etc/password-authenticator.properties` trên coordinator và đặt cấu hình LDAP trong file đó. Ví dụ dưới đây dùng LDAPS, truststore PEM và cách bind kiểu Active Directory; thay hostname, đường dẫn truststore và domain bằng giá trị của hệ thống LDAP.

```properties
password-authenticator.name=ldap
ldap.url=ldaps://ldap-server:636
ldap.ssl.truststore.path=/path/to/ldap_server.pem
ldap.user-bind-pattern=${USER}@corp.example.com
```

Các property cần biết:

| Property | Ý nghĩa và mặc định |
| --- | --- |
| `ldap.url` | URL LDAP, có scheme `ldap://` hoặc `ldaps://`. Dùng `ldap://` cần `ldap.allow-insecure=true`. |
| `ldap.allow-insecure` | Cho phép kết nối LDAP không có TLS; mặc định không bật. |
| `ldap.ssl.keystore.path`, `ldap.ssl.keystore.password` | Keystore PEM hoặc JKS và password tương ứng, nếu LDAP server yêu cầu client certificate. |
| `ldap.ssl.truststore.path`, `ldap.ssl.truststore.password` | Truststore PEM hoặc JKS và password tương ứng để tin cậy certificate LDAP server. |
| `ldap.user-bind-pattern` | Pattern DN/login cho bind user; bắt buộc chứa `${USER}`. |
| `ldap.ignore-referrals` | Bỏ qua referral sang LDAP server khác khi search; mặc định `false`. |
| `ldap.cache-ttl` | Thời gian cache LDAP; mặc định `1h`. |
| `ldap.timeout.connect` | Timeout thiết lập kết nối; mặc định `1m`. |
| `ldap.timeout.read` | Timeout đọc từ kết nối LDAP; mặc định `1m`. |

`ldap.user-bind-pattern` có thể gồm nhiều pattern, ngăn cách bằng dấu `:`. Trino thử theo thứ tự khai báo và dừng khi một lần login thành công hoặc mọi pattern đều thất bại. Mỗi pattern phải chứa `${USER}`.

Tạo hoặc sửa `etc/password-authenticator.properties` trên coordinator với một trong các dạng bind sau, tùy LDAP server đang dùng.

```properties
ldap.user-bind-pattern=${USER}@<domain_name_of_the_server>
```

Với OpenLDAP, tạo hoặc sửa `etc/password-authenticator.properties` trên coordinator bằng DN của user.

```properties
ldap.user-bind-pattern=uid=${USER},<distinguished_name_of_the_user>
```

Ví dụ AD thường là `${USER}@corp.example.com`; ví dụ OpenLDAP là `uid=${USER},OU=America,DC=corp,DC=example,DC=com`.

### 4. Chỉ cho phép thành viên nhóm LDAP

Xác thực password thành công không tự động nghĩa là user được phép vào Trino. Để giới hạn login theo membership, thêm `ldap.user-base-dn` và `ldap.group-auth-pattern` vào cấu hình LDAP cơ bản. Query phải chứa `${USER}`; Trino thay thế biến này bằng username đang đăng nhập. Query thành công thì user được ủy quyền vào coordinator.

Thêm các property sau vào `etc/password-authenticator.properties` trên coordinator khi dùng authorization theo nhóm với bind của chính user.

```properties
ldap.user-base-dn=OU=America,DC=corp,DC=example,DC=com
ldap.group-auth-pattern=(&(objectClass=person)(sAMAccountName=${USER})(memberof=CN=AuthorizedGroup,OU=Asia,DC=corp,DC=example,DC=com))
```

Với Active Directory, pattern thường dùng `sAMAccountName`; với OpenLDAP, pattern thường dùng `uid`. Tạo hoặc sửa `etc/password-authenticator.properties` trên coordinator bằng ví dụ OpenLDAP sau khi group membership được biểu diễn qua `memberOf`.

```properties
ldap.group-auth-pattern=(&(objectClass=inetOrgPerson)(uid=${USER})(memberof=CN=AuthorizedGroup,OU=Asia,DC=corp,DC=example,DC=com))
```

Đối với OpenLDAP, cần bật `memberOf` overlay để query theo `memberOf` hoạt động. Pattern có thể biểu diễn điều kiện phức tạp, ví dụ user thuộc một trong nhiều group. Đặt các truy vấn LDAP cẩn thận: một match quá rộng sẽ cấp quyền login cho nhiều người hơn dự kiến.

### 5. Dùng LDAP service user để tra cứu group

Nếu user thông thường không có quyền search LDAP, Trino có thể dùng một service user. Khi đó Trino:

1. Bind bằng `ldap.bind-dn` và `ldap.bind-password` để chạy `ldap.group-auth-pattern`.
2. Lấy DN của user từ kết quả query nhóm.
3. Bind lại bằng DN đó và password do user cung cấp để xác thực password.

Đây là phương án thay cho việc dùng bind của user để tra cứu group. Trong `etc/password-authenticator.properties` trên coordinator, phải cấu hình đồng thời `ldap.bind-dn`, `ldap.bind-password` và `ldap.group-auth-pattern`; không ghi password thực vào tài liệu hoặc hệ thống quản lý mã nguồn. `ldap.group-auth-pattern` vẫn phải chứa `${USER}` và phải trả về đúng một user DN có thể dùng để bind.

### 6. Kiểm thử bằng Trino CLI

Client CLI cũng phải tin cậy certificate HTTPS của coordinator. Dùng keystore hoặc truststore phù hợp, truyền username LDAP và yêu cầu prompt password.

Chạy lệnh sau từ máy client, thay các placeholder bằng endpoint, certificate store, catalog, schema và user thực tế.

```text
./trino \
  --server https://trino-coordinator.example.com:8443 \
  --keystore-path /tmp/trino.jks \
  --keystore-password password \
  --truststore-path /tmp/trino_truststore.jks \
  --truststore-password password \
  --catalog <catalog> \
  --schema <schema> \
  --user <LDAP user> \
  --password
```

Sau khi đăng nhập, chạy `SELECT current_user;` để xác minh username Trino nhận được, đặc biệt nếu đã bật user mapping. Kiểm thử tối thiểu nên gồm:

- một user có password hợp lệ và thuộc nhóm được phép;
- user có password sai;
- user hợp lệ nhưng không thuộc nhóm được phép;
- username cần map, nếu có user mapping;
- một query bị access control từ chối, để xác minh authentication và authorization là hai lớp độc lập.

### 7. Khắc phục sự cố

- Kiểm tra nội dung và password của JKS/PEM bằng công cụ inspect/validate keystore của Trino; xác nhận truststore chứa CA/certificate đúng cho LDAP server và CLI tin cậy certificate của coordinator.
- Để xem lỗi giữa Trino và LDAP, thêm mức log sau vào cấu hình logging của Trino trong thời gian điều tra, rồi hạ lại sau khi xong.

  Thêm dòng sau vào `etc/log.properties` của Trino.

  ```text
  io.trino.plugin.password=DEBUG
  ```

- Nếu CLI gặp lỗi TLS, chạy executable JAR với `-Djavax.net.debug=ssl` để xem chi tiết SSL handshake.
- Lỗi `No subject alternative names present` thường nghĩa là certificate coordinator không có SAN khớp hostname/IP trong `--server`; cấp lại certificate với SAN phù hợp.
- Từ JDK 8u181, LDAPS kiểm tra endpoint identification chặt hơn. Lỗi `No subject alternative DNS name matching ... found` nên được sửa bằng certificate LDAP có SAN/subject khớp hostname. Có thể tạm thời tắt kiểm tra bằng `-Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true` trong `jvm.config`, nhưng không nên dùng cách này ở production.

### 8. Checklist triển khai

- [ ] HTTPS/TLS đã được bật cho client → coordinator và shared secret đã được cấu hình cho toàn cluster.
- [ ] `http-server.authentication.type=PASSWORD` chỉ được đặt trên coordinator.
- [ ] `etc/password-authenticator.properties` có `password-authenticator.name=ldap`, `ldap.url` và bind pattern phù hợp AD/OpenLDAP.
- [ ] LDAPS, truststore và hostname/SAN certificate LDAP đã được kiểm tra.
- [ ] Chỉ bật `ldap.allow-insecure` nếu có lý do đặc biệt và đã chấp nhận rủi ro.
- [ ] Nếu giới hạn theo nhóm, `ldap.group-auth-pattern` có `${USER}` và được thử với user được phép lẫn user bị từ chối.
- [ ] DN/password của service user được quản lý như secret, nếu dùng service user.
- [ ] Đã kiểm thử CLI qua HTTPS, `SELECT current_user`, user mapping và policy authorization.

---

## User mapping cho Trino

> Tóm tắt theo [User mapping — Trino current](https://trino.io/docs/current/security/user-mapping.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-12).

User mapping chuyển identity do cơ chế authentication trả về thành username đơn giản mà Trino dùng nội bộ. Nó đặc biệt hữu ích khi identity có dạng `alice@example.com`, Kerberos principal hoặc certificate subject như `CN=Alice Smith,...`.

User mapping là bước **sau xác thực**, không thay thế password file, OAuth, Kerberos hay access control. Username sau mapping là username được các rule access control và group provider sử dụng.

Với password-file authentication, password file kiểm tra **username đầu vào** trước, rồi user mapping mới đổi principal đã xác thực thành Trino user. Vì vậy mapping `alice@example.com → alice` cần entry `alice@example.com` trong `password.db`, còn group file và ACL rule dùng `alice`.

### 1. Khi nào cần dùng

Chỉ thêm mapping khi authentication provider trả về tên phức tạp (ví dụ email) nhưng policy hoặc group muốn dùng tên chuẩn hóa (ví dụ `alice`).

User mapping được cấu hình trên **coordinator**. Thêm property mapping vào `etc/config.properties`; nếu dùng file mapping, tạo thêm `etc/user-mapping.json`. Không thêm các property này vào worker.

### 2. Chọn một trong hai cách mapping

| Cách | Phù hợp khi | Hành vi khi không khớp |
| --- | --- | --- |
| Pattern mapping | Mọi username cùng một format regex. | Authentication bị từ chối. |
| File mapping rules | Có nhiều format, cần ngoại lệ hoặc cần chặn một số identity. | Authentication bị từ chối. |

Cả hai đều dựa trên regex. Với một authentication type, chọn phương án phù hợp và kiểm thử bằng username thật trước khi triển khai rộng.

### 3. Pattern mapping rule

Pattern phải capture username đầu ra ở group đầu tiên; Trino dùng **capture group đầu tiên** (`$1`) làm username kết quả. Với username dạng email, mẫu Trino tách thành hai group để chuyển `alice@example.com` thành `alice`:

Thêm property sau vào `etc/config.properties` trên coordinator. Dùng pattern mapping thay cho file mapping; không đặt property này trong `user-mapping.json`.

```properties
http-server.authentication.password.user-mapping.pattern=(.*)(@.*)
```

Nếu regex không khớp, user không thể đăng nhập. `PASSWORD` là authentication type dùng chung cho password-file, LDAP và Salesforce.

> Cảnh báo: một email-only pattern như trên sẽ không khớp username không có `@` và vì thế từ chối chúng. Nếu cần hỗ trợ nhiều dạng username, dùng file rule có ngoại lệ/catch-all được review kỹ.

#### Property theo authentication type

| Authentication type | Property pattern |
| --- | --- |
| Password (file, LDAP, Salesforce) | `http-server.authentication.password.user-mapping.pattern` |
| OAuth2 | `http-server.authentication.oauth2.user-mapping.pattern` |
| Certificate | `http-server.authentication.certificate.user-mapping.pattern` |
| Header | `http-server.authentication.header.user-mapping.pattern` |
| JSON Web Token | `http-server.authentication.jwt.user-mapping.pattern` |
| Kerberos | `http-server.authentication.krb5.user-mapping.pattern` |
| Insecure | `http-server.authentication.insecure.user-mapping.pattern` |

### 4. File mapping rules

Dùng file JSON khi cần nhiều rule hoặc một deny rule cụ thể. Rule được xử lý từ trên xuống dưới; **rule đầu tiên khớp** quyết định kết quả. Không có rule khớp thì authentication bị từ chối.

Mỗi rule gồm:

| Field | Bắt buộc | Ý nghĩa |
| --- | --- | --- |
| `pattern` | Có | Regex khớp username từ authentication provider. |
| `user` | Không | Chuỗi thay thế; mặc định là `$1`. Có thể dùng capture group đặt tên. |
| `allow` | Không | Boolean cho phép/từ chối identity đã khớp. |
| `case` | Không | `keep` (mặc định), `lower` hoặc `upper` cho username sau mapping. |

Tạo `etc/user-mapping.json` và đặt toàn bộ JSON dưới đây vào file đó. Sau đó thêm property `...user-mapping.file` vào `etc/config.properties` như phần kế tiếp; không đặt JSON trong `config.properties`.

Trong `etc/user-mapping.json`, đặt mẫu Trino sau để chặn `test@example.com`, chuyển `alice@example.com` thành `alice`, dùng named group cho region, và chuẩn hóa một domain thành uppercase:

```json
{
    "rules": [
        {
            "pattern": "test@example\\.com",
            "allow": false
        },
        {
            "pattern": "(.+)@example\\.com"
        },
        {
            "pattern": "(?<user>.+)@(?<region>.+)\\.example\\.com",
            "user": "${user}_${region}"
        },
        {
            "pattern": "(.*)@uppercase.com",
            "case": "upper"
        }
    ]
}
```

#### Bật file mapping

Thêm property sau vào `etc/config.properties` trên coordinator. Giá trị `etc/user-mapping.json` phải khớp đường dẫn của file rule đã tạo:

```properties
http-server.authentication.password.user-mapping.file=etc/user-mapping.json
```

Không để đồng thời property `...user-mapping.pattern`. Sau khi thêm/chuyển property mapping hoặc đổi JSON, restart coordinator theo cách triển khai của bạn. Thay đổi nội dung JSON cần được kiểm thử; không giả định nó dùng refresh period của file ACL.

#### Property file theo authentication type

Mọi property trong bảng này đều đặt trong **`etc/config.properties` trên coordinator**. Thay `password` bằng authentication type đang dùng và chọn đúng một property mapping cho type đó.

| Authentication type | Property file |
| --- | --- |
| Password (file, LDAP, Salesforce) | `http-server.authentication.password.user-mapping.file` |
| OAuth2 | `http-server.authentication.oauth2.user-mapping.file` |
| Certificate | `http-server.authentication.certificate.user-mapping.file` |
| Header | `http-server.authentication.header.user-mapping.pattern` |
| JSON Web Token | `http-server.authentication.jwt.user-mapping.file` |
| Kerberos | `http-server.authentication.krb5.user-mapping.file` |
| Insecure | `http-server.authentication.insecure.user-mapping.file` |

> Trang Trino hiện liệt kê property Header là `...user-mapping.pattern` cả trong bảng file mapping. Kiểm tra tài liệu đúng version/authenticator trước khi áp dụng Header authentication.

### 5. Kiểm thử và liên hệ với ACL

1. Dùng một identity mà bạn biết username đầu vào và expected username sau mapping.
2. Đăng nhập qua endpoint của coordinator bằng CLI. Lệnh dưới là **ví dụ giả định**: password file phải có entry cho username đầu vào `alice@example.com` (hoặc dùng LDAP/certificate provider).

   ```powershell
   trino --server https://trino.example.com --user alice@example.com --password
   ```

3. Kiểm tra username Trino thực nhận:

   ```sql
   SELECT current_user;
   ```

4. Kiểm thử một rule access control dựa trên username/group, ví dụ từ [phần file-based access control](#file-based-access-control-cho-trino).

Đặt deny/ngoại lệ cụ thể trước allow rule rộng. Cẩn thận với `(.*)`: nó cho phép mọi username phù hợp và có thể làm identity ngoài dự kiến vào cluster.

### 6. Checklist

- [ ] Chỉ bật mapping khi authentication trả username cần chuẩn hóa.
- [ ] Mapping property nằm trên coordinator và đúng authentication type.
- [ ] Regex có capture group/JSON rule có kết quả username dự kiến.
- [ ] Rule deny cụ thể đứng trước rule allow rộng.
- [ ] Username đầu vào khớp entry của authenticator/password file; username **sau mapping** khớp group file/LDAP và access-control rule.
- [ ] Đã test `SELECT current_user` qua HTTPS với cả user cho phép và user bị từ chối.

---

## Group mapping cho Trino

> Tóm tắt theo [Group mapping — Trino current](https://trino.io/docs/current/security/group-mapping.html) (trang hiển thị Trino 482 khi đối chiếu ngày 2026-07-12).

Group provider ánh xạ username vào các group để access control và resource group management có thể cấp quyền theo nhóm thay vì từng user. Nó không tạo authentication, role hay quyền; sau khi provider trả group, system access control mới quyết định user được làm gì.

### 1. Cấu hình và phạm vi

Group provider được cấu hình bằng `etc/group-provider.properties` trên **coordinator**. Giá trị `group-provider.name` chỉ có thể là `file` hoặc `ldap`; toàn bộ config của provider đã chọn nằm trong cùng file này.

User mapping và group mapping phải dùng cùng username chuẩn hóa. Nếu [phần user mapping](#user-mapping-cho-trino) chuyển `alice@example.com` thành `alice`, group file/LDAP phải có member `alice`, không phải email gốc.

### 2. Property chung

**Tạo hoặc sửa `etc/group-provider.properties` trên coordinator**, rồi thêm property `group-provider.name` để chọn provider:

```properties
group-provider.name=file
```

| Property | Giá trị/ý nghĩa |
| --- | --- |
| `group-provider.name` | `file` hoặc `ldap`. |
| `group-provider.group-case` | Chuẩn hóa tên group: `keep` (mặc định), `upper`, hoặc `lower`. |

Chọn một quy ước case và dùng nhất quán trong group source lẫn access-control regex. Ví dụ group file trả `finance` nhưng ACL tìm `FINANCE` sẽ không khớp nếu không chuẩn hóa phù hợp.

### 3. File group provider

Phù hợp với môi trường nhỏ hoặc group membership được quản lý cùng cấu hình.

**Tạo `etc/group-provider.properties` trên coordinator và thêm block sau.** Giá trị `file.group-file` là đường dẫn tới file membership; trong ví dụ, file đó là `etc/group.txt`.

```properties
group-provider.name=file
group-provider.group-case=lower
file.group-file=etc/group.txt
file.refresh-period=5s
```

`file.refresh-period` là chu kỳ đọc lại group file, mặc định `5s`. Nếu đặt membership ở đường dẫn khác, thay `etc/group.txt` bằng đường dẫn đó.

#### Định dạng group file

**Tạo `etc/group.txt` (hoặc file đã khai báo trong `file.group-file`) và thêm các dòng membership dưới đây.** Chúng không phải property và không được chép vào `group-provider.properties`.

Trong `etc/group.txt` (hoặc file đã khai báo trong `file.group-file`), mỗi dòng là một group; dấu `:` ngăn cách group và members, còn members cách nhau bằng dấu phẩy:

```text
group_name:user_1,user_2,user_3
```

Trong cùng file group đó, thêm các dòng sau nếu dùng convention lower-case với ACL:

```text
finance:alice,bob
human_resources:carol
```

Sau khi file được nạp, cập nhật membership thường có hiệu lực trong vòng `file.refresh-period`; thay đổi `group-provider.properties` cần restart coordinator.

### 4. LDAP group provider

Dùng LDAP khi group membership đã được quản lý tập trung. **Tạo hoặc sửa `etc/group-provider.properties` trên coordinator và thay cấu hình file provider bằng block LDAP.** Không giữ property `file.*` khi đã chọn LDAP. Bắt đầu bằng:

```properties
group-provider.name=ldap
```

#### Property LDAP quan trọng

| Nhóm | Property |
| --- | --- |
| Kết nối | `ldap.url` (`ldap://host:389` hoặc `ldaps://host:636`), `ldap.allow-insecure` (mặc định `false`), `ldap.timeout.connect`/`ldap.timeout.read` (mặc định `1m`). |
| TLS tới LDAP | `ldap.ssl.keystore.path`, `ldap.ssl.keystore.password`, `ldap.ssl.truststore.path`, `ldap.ssl.truststore.password`. |
| Bind/tìm user | `ldap.admin-user`, `ldap.admin-password`, `ldap.user-base-dn`, `ldap.user-search-filter`. `{0}` trong filter được thay bằng username Trino. |
| Tên group | `ldap.group-name-attribute`, ví dụ `cn`. |
| Referral | `ldap.ignore-referrals` (mặc định `false`). |

Không ghi password LDAP thật trong file tracked. Giá trị `ldap.admin-password=your_password` trong các mẫu chỉ là placeholder. Nếu `group-provider.properties` cần bind credential, dùng cơ chế quản lý secret phù hợp với cách triển khai của bạn; không commit secret vào Git. Ưu tiên `ldaps://` hoặc truststore phù hợp; không bật `ldap.allow-insecure=true` để “sửa” lỗi certificate.

#### Chọn cách resolve group

`ldap.use-group-filter` mặc định `true`:

| Cách | Property bắt buộc |
| --- | --- |
| Search-based (mặc định) | `ldap.group-base-dn`, `ldap.group-search-filter`, `ldap.group-search-member-attribute`. Trino tìm group entries có user DN là member. |
| Attribute-based | Đặt `ldap.use-group-filter=false` và cấu hình `ldap.user-member-of-attribute`, thường là `memberOf`. Trino đọc danh sách group từ user attribute. |

#### Mẫu OpenLDAP: search-based

**Thay nội dung `etc/group-provider.properties` bằng toàn bộ block này**; đây là phương án thay thế cho file provider, không phải một file bổ sung:

```properties
group-provider.name=ldap
group-provider.group-case=lower

ldap.url=ldap://ldap.example.com:389
ldap.admin-user=cn=admin,dc=example,dc=com
ldap.admin-password=your_password
ldap.group-name-attribute=cn
ldap.user-base-dn=ou=users,dc=example,dc=com
ldap.user-search-filter=(uid={0})
ldap.use-group-filter=true
ldap.group-base-dn=ou=groups,dc=example,dc=com
ldap.group-search-filter=(cn=trino_*)
ldap.group-search-member-attribute=member
```

#### Mẫu Active Directory: attribute-based, single query

**Thay nội dung `etc/group-provider.properties` bằng toàn bộ block này**; thay các DN/filter/credential bằng giá trị môi trường thực tế:

```properties
group-provider.name=ldap
group-provider.group-case=lower

ldap.url=ldaps://ad.example.com:636
ldap.admin-user=cn=admin,dc=example,dc=com
ldap.admin-password=your_password
ldap.group-name-attribute=cn
ldap.user-base-dn=ou=users,dc=example,dc=com
ldap.user-search-filter=(sAMAccountName={0})
ldap.use-group-filter=false

ldap.user-member-of-attribute=memberOf
```

Các giá trị DN, attribute và filter phụ thuộc LDAP schema thực tế; không copy nguyên mẫu vào production.

### 5. Dùng group trong access control

Trino chuyển group đã resolve đến system access control. **Thêm section `catalogs` dưới đây vào JSON rule file ACL đã cấu hình** (ví dụ `etc/rules.json`), không đặt JSON này trong `group-provider.properties`. File ACL có thể dùng `group` regex, ví dụ:

```json
{
  "catalogs": [
    {
      "group": "finance|human_resources",
      "catalog": "hive",
      "allow": "read-only"
    }
  ]
}
```

Đây chỉ là ví dụ. Hãy điều chỉnh catalog, schema/table và group theo environment trước khi kiểm thử. Xem [phần file-based access control](#file-based-access-control-cho-trino) để biết thứ tự rule “first match wins”.

### 6. Kiểm thử

1. Tạo `etc/group-provider.properties`. Nếu dùng file provider, tạo thêm `etc/group.txt` (hoặc file đã khai báo); nếu dùng LDAP, chỉ dùng `group-provider.properties`.
2. Restart coordinator sau khi đổi provider config. Với file provider, thay đổi membership thường có hiệu lực sau `file.refresh-period`.
3. Đăng nhập bằng user thuộc một group đã biết, rồi chạy:

   ```sql
   SELECT current_user;
   ```

4. Thử một query mà file ACL cho phép group đó trên **catalog thực tế**, và thử một user không thuộc group để xác nhận bị từ chối.

### 7. Checklist

- [ ] Chọn duy nhất một provider: `file` hoặc `ldap`.
- [ ] Provider config chỉ nằm trên coordinator.
- [ ] Username trong group source khớp username sau authentication/user mapping.
- [ ] Case của group nhất quán với ACL regex.
- [ ] LDAP URL/TLS/truststore và bind credential được bảo vệ; không commit secret.
- [ ] ACL rule dùng đúng catalog/schema/table trong môi trường triển khai, không chỉ mẫu từ tài liệu.
- [ ] Đã test allow và deny bằng user thật qua HTTPS.

---

## File-based access control cho Trino

> Tóm tắt theo [File-based access control — Trino 482](https://trino.io/docs/current/security/file-system-access-control.html). Cập nhật tham chiếu: 2026-07-11.

File-based access control (file ACL) là cơ chế **phân quyền** của Trino. Nó đọc các rule JSON do quản trị viên quản lý để quyết định user/role/group được dùng tài nguyên hay thao tác nào. Nó không thay thế cơ chế **xác thực** như password file, OAuth hoặc Kerberos: xác thực cho biết người dùng là ai, còn file ACL quyết định người đó được làm gì.

Các block cấu hình dưới đây giữ nguyên tên property, giá trị mẫu và cú pháp JSON của tài liệu Trino. Chỉ phần giải thích được viết lại bằng tiếng Việt.

### 1. Chọn phạm vi áp dụng

Trino có hai dạng file ACL:

| Dạng | Khi dùng | Phạm vi |
| --- | --- | --- |
| **System-level** | Cần một chính sách chung cho cả cluster. | Một file JSON điều khiển catalog, schema, table, function, procedure, query, impersonation, system information, v.v. |
| **Catalog-level** | Cần policy riêng cho một catalog/connector hỗ trợ `FILE` (ví dụ Iceberg). | Một file JSON cho từng catalog; hỗ trợ schema, table, cột, function và session property trong catalog đó. |

System-level thường là điểm bắt đầu phù hợp để chặn/mở quyền trên toàn cluster. Catalog-level là lớp phân quyền theo connector, không phải mọi connector đều hỗ trợ.

### 2. Mô hình đánh giá rule — phần quan trọng nhất

- Các rule trong mỗi danh sách được đọc **từ trên xuống dưới**; **rule đầu tiên khớp** được áp dụng. Đặt ngoại lệ/chặn cụ thể trước rule cho phép rộng hơn.
- Nếu một rule section đã có nhưng không có rule nào khớp, phần lớn thao tác bị từ chối. Không nên dựa vào các default ngầm; hãy thêm rule rõ ràng, gồm cả rule chặn cuối nếu chính sách cần deny-by-default.
- Các trường nhận diện như `user`, `role`, `group`, `catalog`, `schema`, `table`, `function`, `procedure` là **regular expression**; khi bỏ qua, mặc định thường là `.*`.
- Rule `role` khớp nếu có ít nhất một role đang bật khớp regex. Rule `group` khớp nếu user thuộc ít nhất một group khớp regex; vì vậy phải cấu hình [group provider](https://trino.io/docs/current/security/group-provider.html) nếu dùng `group`.
- `information_schema` là ngoại lệ: rule catalog/schema/table trong trang này không áp dụng cho các table do hệ thống định nghĩa trong schema đó.
- Với catalog/schema/table, tài liệu nêu rằng khi hoàn toàn không cung cấp rule thì quyền được cấp. Trong file ACL JSON đã cấu hình (ví dụ `etc/rules.json`), một section rỗng có thể được dùng để gỡ quyền cấp mặc định:

```json
{
  "schemas": []
}
```

- `SHOW` không đồng nghĩa với toàn quyền: catalog/schema/table chỉ hiện khi user có ít nhất một quyền trên chính đối tượng hoặc đối tượng lồng bên trong nó. Catalog `system` mặc định có thể truy cập; thêm catalog rule để ghi đè hành vi này.

### 3. Bật system-level file ACL

Tạo `etc/access-control.properties` trên coordinator. Hai property sau là bắt buộc; `access-control.name` phải là `file` và `security.config-file` trỏ đến JSON rule file.

```properties
access-control.name=file
security.config-file=etc/rules.json
```


#### Đọc rule JSON từ HTTP (tùy chọn)

Nếu endpoint trả về JSON bọc rule trong key `data`, dùng JSON Pointer RFC 6901 để chọn object chứa rule:

```properties
access-control.name=file
security.config-file=http://trino-test/config
security.json-pointer=/data
```

Khi file/endpoint trả trực tiếp một JSON object chứa các rule, không cần `security.json-pointer`.

#### Nạp lại rule

Mặc định, thay đổi rule cần restart Trino. Để Trino tự đọc lại file/endpoint theo chu kỳ, thêm:

```properties
security.refresh-period=1s
```

Chọn chu kỳ hợp lý cho vận hành; refresh không thay thế việc kiểm thử policy trước khi đưa vào môi trường dùng chung.

### 4. Catalog, schema và table rules

Ba section chính trong `rules.json` là `catalogs`, `schemas`, `tables`.

#### 4.1 Catalog rules

Mỗi rule có các trường tùy chọn `user`, `role`, `group`, `catalog` và trường bắt buộc `allow`.

`allow` nhận `all`, `read-only`, hoặc `none` (mặc định là `none`). `all` chỉ nói catalog rule không hạn chế thêm; schema/table rule vẫn có thể chặn thao tác. `read-only` chặn ghi. Giá trị boolean cũ vẫn tương thích: `true` tương đương `all`, `false` tương đương `none`.

Trong file ACL JSON đã cấu hình (ví dụ `etc/rules.json`), thêm section `catalogs` sau để cho phép role `admin` vào `mysql`/`system`, các group nhất định vào `postgres`, mọi user vào `hive`, và cho `alice` chỉ đọc `postgresql`. Rule cuối chặn `system` đối với các user không đã khớp rule `admin` ở trên:

```json
{
  "catalogs": [
    {
      "role": "admin",
      "catalog": "(mysql|system)",
      "allow": "all"
    },
    {
      "group": "finance|human_resources",
      "catalog": "postgres",
      "allow": true
    },
    {
      "catalog": "hive",
      "allow": "all"
    },
    {
      "user": "alice",
      "catalog": "postgresql",
      "allow": "read-only"
    },
    {
      "catalog": "system",
      "allow": "none"
    }
  ]
}
```

Thứ tự là một phần của policy: ví dụ nếu muốn chặn `alice` trước một rule cho phép tất cả user, rule của `alice` phải đứng trước rule rộng đó.

#### 4.2 Schema rules

Schema rule gồm `user`, `role`, `group`, `catalog`, `schema` (đều tùy chọn) và `owner` (bắt buộc, boolean). `owner: true` cấp quyền sở hữu schema, cần cho nhiều thao tác DDL. Thêm section `schemas` sau vào file ACL JSON đã cấu hình (ví dụ `etc/rules.json`).

```json
{
  "schemas": [
    {
      "role": "admin",
      "schema": ".*",
      "owner": true
    },
    {
      "user": "guest",
      "owner": false
    },
    {
      "catalog": "default",
      "schema": "default",
      "owner": true
    }
  ]
}
```

#### 4.3 Table rules, row filter và column mask

Table rule có `user`, `role`, `group`, `catalog`, `schema`, `table` (tùy chọn), cùng `privileges` (bắt buộc). Các giá trị `privileges` là:

`SELECT`, `INSERT`, `DELETE`, `UPDATE`, `OWNERSHIP`, `GRANT_SELECT`.

Rule còn có thể chứa:

- `columns`: danh sách ràng buộc cột. Mỗi item có `name`, và tùy chọn `allow: false`, `mask`, `mask_environment`.
- `filter`: biểu thức boolean lọc hàng (row-level filter).
- `filter_environment`: context dùng khi đánh giá filter.
- `mask_environment`: context dùng khi đánh giá subquery trong mask.

`mask` có thể dùng biểu thức điều kiện như `IF` hoặc `CASE`. Trong file ACL JSON đã cấu hình (ví dụ `etc/rules.json`), thêm section `tables` sau để thể hiện role admin toàn quyền, user bị chặn, row filter theo `current_user`, chặn cột `address` và mask cột `SSN`:

```json
{
  "tables": [
    {
      "role": "admin",
      "privileges": ["SELECT", "INSERT", "DELETE", "UPDATE", "OWNERSHIP"]
    },
    {
      "user": "banned_user",
      "privileges": []
    },
    {
      "catalog": "default",
      "schema": "hr",
      "table": "employee",
      "privileges": ["SELECT"],
      "filter": "user = current_user",
      "filter_environment": {
        "user": "system_user"
      }
    },
    {
      "catalog": "default",
      "schema": "default",
      "table": ".*",
      "privileges": ["SELECT"],
      "columns" : [
         {
            "name": "address",
            "allow": false
         },
         {
            "name": "SSN",
            "mask": "'XXX-XX-' + substring(credit_card, -4)",
            "mask_environment": {
              "user": "system_user"
            }
         }
      ]
    }
  ]
}
```

#### 4.4 Liên hệ giữa SQL và quyền

Đây là các quan hệ cần nhớ khi thiết kế policy system-level:

| Thao tác | Catalog rule | Quyền bổ sung |
| --- | --- | --- |
| `SHOW CATALOGS` | Luôn được phép | Visibility vẫn phụ thuộc quyền lồng bên trong. |
| `SHOW SCHEMAS`, `SHOW TABLES`, `SHOW COLUMNS` | `read-only` | Cần catalog/schema/table có thể nhìn thấy. |
| `SELECT` từ table | `read-only` | `SELECT` trên table. |
| `SELECT` từ view | `read-only` | `SELECT` và `GRANT_SELECT`. |
| `INSERT`, `DELETE`, `UPDATE` | `all` | Lần lượt `INSERT`, `DELETE`, `UPDATE`. |
| `CREATE TABLE`/`VIEW`, `DROP`, `ALTER`, `COMMENT` | `all` | Schema/table owner tùy lệnh; rename yêu cầu ownership trên cả đối tượng cũ và mới. |
| `CREATE SCHEMA`, `DROP SCHEMA`, `ALTER SCHEMA` | `read-only` hoặc `all` tùy lệnh | Ownership schema. |

Không phải connector nào cũng hỗ trợ mọi thao tác hoặc catalog user-defined function.

### 5. Các rule system-level khác

| Section | Mục đích và trường/quyền cần nhớ | Default đáng chú ý |
| --- | --- | --- |
| `functions` | `user`, `role`, `group`, `catalog`, `schema`, `function`; `privileges`: `EXECUTE`, `GRANT_EXECUTE`, `OWNERSHIP`. | Nếu section không có, chỉ function trong `system.builtin` chạy được. Function trong `system.builtin` luôn truy cập được và không thể bị rule ghi đè. Cẩn trọng khi cấp quyền schema `system` của catalog vì table function như `query` có thể truy cập/sửa dữ liệu bên dưới. |
| `procedures` | Cho `CALL`; dùng các trường tương tự function và `procedure`; quyền `EXECUTE`, `GRANT_EXECUTE`. | Nếu section không có, chỉ procedure trong `system.builtin` chạy được. Table procedure (`ALTER TABLE ... EXECUTE`) không có privilege file ACL riêng, nên thực tế đều được cho phép. |
| `system_session_properties` | `user`, `role`, `group`, `property`, `allow`. | Không có section: mọi user được đặt system session property. |
| `catalog_session_properties` | Như trên, thêm `catalog`. | Không khớp rule: từ chối đặt property. |
| `queries` | `user`, `role`, `group`, `queryOwner`, `allow`: `execute`, `view`, `kill`. | User luôn xem/kill query của chính họ. Rule có `queryOwner` không được chứa `execute`. |
| `impersonation` | `original_user`, `original_role`, `new_user` (bắt buộc), `allow`. `new_user` có thể dùng capture group từ `original_user`, ví dụ `$1`. | Không có impersonation/principal rule: impersonation không được phép. |
| `principals` | Mapping principal sang user. | **Deprecated**; dùng user mapping cộng impersonation rules thay thế. |
| `system_information` | Đọc REST endpoint nhạy cảm, system information function/System connector, hoặc graceful shutdown; `allow`: `read`, `write`. | Không có rule: từ chối toàn bộ system information. Các endpoint `GET /v1/info`, `/v1/info/state`, `/v1/status` luôn public. |
| `authorization` | Đổi owner qua `ALTER SCHEMA/TABLE/VIEW ... SET AUTHORIZATION`; `original_user/group/role`, `new_user` và/hoặc `new_role`, `allow`. | Cần có ít nhất `new_user` hoặc `new_role`, và người chạy lệnh vẫn cần `OWNERSHIP`. |

#### Mẫu session property và query rule

Trong file ACL JSON đã cấu hình (ví dụ `etc/rules.json`), thêm section `system_session_properties` và/hoặc `catalog_session_properties` sau:

```json
{
    "system_session_properties": [
        {
            "role": "admin",
            "allow": true
        },
        {
            "user": "banned_user",
            "allow": false
        },
        {
            "property": "resource_overcommit",
            "allow": true
        }
    ],
    "catalog_session_properties": [
        {
            "role": "admin",
            "allow": true
        },
        {
            "user": "banned_user",
            "allow": false
        },
        {
            "catalog": "hive",
            "property": "bucket_execution_enabled",
            "allow": true
        }
    ]
}
```

Trong cùng file ACL JSON đó, thêm section `queries` sau nếu muốn giới hạn chạy, xem hoặc hủy query:

```json
{
  "queries": [
    {
      "role": "admin",
      "allow": ["execute", "kill", "view"]
    },
    {
      "user": "alice",
      "allow": ["execute", "kill"]
    },
    {
      "group": "contractors",
      "queryOwner": "alice|dave",
      "allow": ["view"]
    },
    {
      "allow": ["execute"]
    }
  ]
}
```

#### Mẫu impersonation, system information và ownership authorization

Trong file ACL JSON đã cấu hình (ví dụ `etc/rules.json`), thêm section `impersonation` sau để kiểm soát impersonation:

```json
{
    "impersonation": [
        {
            "original_role": "admin",
            "new_user": "bob",
            "allow": false
        },
        {
            "original_role": "admin",
            "new_user": ".*"
        },
        {
            "original_user": ".*",
            "new_user": "test"
        },
        {
            "original_user": "team_(.*)",
            "new_user": "team_$1_sandbox",
            "allow": true
        }
    ]
}
```

Trong cùng file ACL JSON đó, thêm section `system_information` sau để kiểm soát thông tin hệ thống:

```json
{
  "system_information": [
    {
      "role": "admin",
      "allow": ["read", "write"]
    },
    {
      "user": "alice",
      "allow": ["read"]
    }
  ]
}
```

Trong cùng file ACL JSON đó, thêm các section `authorization`, `schemas` và `tables` sau cho ví dụ đổi owner:

```json
{
  "authorization": [
    {
      "original_role": "admin",
      "new_user": "bob",
      "allow": false
    },
    {
      "original_role": "admin",
      "new_user": ".*",
      "new_role": ".*"
    }
  ],
  "schemas": [
    {
      "role": "admin",
      "owner": true
    }
  ],
  "tables": [
    {
      "role": "admin",
      "privileges": ["OWNERSHIP"]
    }
  ]
}
```

Nếu đặt `management.user`, user cố định này vẫn phải được `system_information` rule cho phép. Khi management interface chạy qua HTTPS, bật thêm `management.user.https-enabled` nếu cần áp dụng fixed user ở HTTPS.

### 6. Catalog-level file ACL

Catalog-level ACL được cấu hình trong file properties của **chính catalog/connector**. Ví dụ với Iceberg, thêm các property sau vào file catalog (chẳng hạn `etc/catalog/iceberg.properties`) để dùng file `rules.json` riêng:

```properties
iceberg.security=FILE
security.config-file=etc/catalog/rules.json
```

Xem tài liệu connector để xác nhận connector hỗ trợ `FILE`. Rule file catalog-level có các section, cũng được xử lý theo thứ tự từ trên xuống:

1. `schemas`
2. `tables`
3. `session_properties`
4. `functions`

Khác biệt chính so với system-level:

- `schemas`: `user`, `group`, `schema`, `owner`; không có `catalog`/`role` vì file đã gắn với một catalog.
- `tables`: `user`, `group`, `schema`, `table`, `privileges`, `columns`, `filter`, `filter_environment`; column/mask dùng cùng ý nghĩa như system-level.
- `session_properties`: `user`, `group`, `property`, `allow`.
- `functions`: `user`, `group`, `schema`, `function`, `privileges` (`EXECUTE`, `GRANT_EXECUTE`, `OWNERSHIP`). Không có function rule thì access không được phép.
- Các rule này cũng không áp dụng cho table hệ thống trong `information_schema`.

Mẫu đầy đủ sau cho một catalog cho thấy ownership schema, table privilege/row filter/column mask và session property:

```json
{
  "schemas": [
    {
      "user": "admin",
      "schema": ".*",
      "owner": true
    },
    {
      "group": "finance|human_resources",
      "schema": "employees",
      "owner": true
    },
    {
      "user": "guest",
      "owner": false
    },
    {
      "schema": "default",
      "owner": true
    }
  ],
  "tables": [
    {
      "user": "admin",
      "privileges": ["SELECT", "INSERT", "DELETE", "UPDATE", "OWNERSHIP"]
    },
    {
      "user": "banned_user",
      "privileges": []
    },
    {
      "schema": "hr",
      "table": "employee",
      "privileges": ["SELECT"],
      "filter": "user = current_user"
    },
    {
      "schema": "default",
      "table": ".*",
      "privileges": ["SELECT"],
      "columns" : [
         {
            "name": "address",
            "allow": false
         },
         {
            "name": "ssn",
            "mask": "'XXX-XX-' + substring(credit_card, -4)",
            "mask_environment": {
              "user": "admin"
            }
         }
      ]
    }
  ],
  "session_properties": [
    {
      "property": "force_local_scheduling",
      "allow": true
    },
    {
      "user": "admin",
      "property": "max_split_size",
      "allow": true
    }
  ]
}
```

### 7. Kiểm thử trước khi viết policy thật

Để xác nhận system-level file ACL đã được nạp, tài liệu Trino đề xuất tạm thời chặn catalog `system`:

```json
{
  "catalogs": [
    {
      "catalog": "system",
      "allow": "none"
    }
  ]
}
```

Sau khi restart (hoặc chờ refresh nếu đã cấu hình), chạy bằng Trino CLI:

```text
trino> SELECT * FROM system.runtime.nodes;
Query 20200824_183358_00000_c62aw failed: Access Denied: Cannot access catalog system
```

Sau khi xác minh, bỏ rule chặn thử nghiệm và thay bằng policy thực tế. Kiểm thử tối thiểu nên có user/role cho phép, user bị chặn, truy vấn `SHOW`, `SELECT`, thao tác ghi (nếu có), và một trường hợp row filter/column mask nếu policy dùng chúng.

### 8. Checklist vận hành an toàn

- Giữ `access-control.properties` và JSON rule dưới quyền kiểm soát thay đổi; JSON sai có thể làm coordinator không khởi động hoặc chặn user ngoài dự kiến.
- Luôn review thứ tự rule: deny/exceptions cụ thể đứng trước allow rộng.
- Không cấp `OWNERSHIP`, `GRANT_SELECT`, `GRANT_EXECUTE` hay quyền schema `system` một cách rộng rãi.
- Quyết định rõ cách xử lý `information_schema` và catalog `system`; đừng giả định chúng bị bảo vệ giống table thường.
- Nếu dùng group/role, xác minh mapping và role đang bật bằng đúng user thực tế.
- Dùng refresh period khi cần cập nhật nhanh, nhưng triển khai policy quan trọng theo quy trình test/rollback.

---

## Dùng biến môi trường cho secret trong Trino

Trino có thể thay thế giá trị của bất kỳ property trong `config.properties` hoặc catalog properties file bằng biến môi trường. Cách này giữ password, access key và shared secret ngoài các file cấu hình được quản lý bằng Git. Trino đọc biến khi khởi động node; hệ thống provision/deploy phải cấp biến cho đúng tiến trình coordinator và worker.

Biến môi trường chỉ tách secret khỏi file cấu hình, không tự biến nó thành an toàn tuyệt đối. Giới hạn quyền xem cấu hình deploy, metadata container và môi trường tiến trình; không ghi giá trị biến vào log. Với hạ tầng cloud, ưu tiên identity ngắn hạn hoặc IAM role khi connector hỗ trợ, thay vì access key tĩnh.

### 1. Cú pháp và phạm vi

Trino dùng cú pháp `${ENV:TEN_BIEN}`. Việc thay thế áp dụng cho mọi properties file mà Trino nạp, bao gồm `etc/config.properties` và `etc/catalog/*.properties`. Tên biến phân biệt rõ mục đích để dễ cấp quyền và xoay vòng, ví dụ `POSTGRES_PASSWORD`, `S3_ACCESS_KEY` và `S3_SECRET_KEY`.

Đặt biến trong môi trường của **mọi node cần dùng property đó** trước khi khởi động Trino. Một biến không có mặt hoặc có giá trị không hợp lệ khiến cấu hình không dùng được; kiểm tra log khởi động của node thay vì thay bằng một giá trị mặc định bí mật trong Git.

### 2. Password connector

Tạo hoặc sửa `etc/catalog/postgresql.properties` và đặt password kết nối qua biến môi trường như sau.

```properties
connector.name=postgresql
connection-url=jdbc:postgresql://database.example.com:5432/analytics
connection-user=analytics_reader
connection-password=${ENV:POSTGRES_PASSWORD}
```

`POSTGRES_PASSWORD` phải được cấp cho tất cả coordinator và worker nạp catalog này. Khi xoay vòng password, cập nhật secret ở hệ thống provision trước, rồi restart các node để nạp cấu hình mới.

### 3. Static key cho S3

Static access key chỉ phù hợp khi không thể dùng AWS default credential chain, IAM role hoặc web identity. Khi dùng static key, cả hai biến phải được cấp cho mọi node nạp catalog truy cập S3.

Tạo hoặc sửa catalog properties file, ví dụ `etc/catalog/iceberg.properties`, và bật S3 native file system với credential từ biến môi trường.

```properties
fs.s3.enabled=true
s3.aws-access-key=${ENV:S3_ACCESS_KEY}
s3.aws-secret-key=${ENV:S3_SECRET_KEY}
```

`s3.aws-access-key` và `s3.aws-secret-key` là static credential trong chế độ xác thực `DEFAULT`. Nếu không đặt static key, Trino dùng AWS default credentials chain; đó thường là lựa chọn tốt hơn trên hạ tầng AWS có identity được quản lý.

### 4. Shared secret nội bộ

Khi cluster dùng client authentication hoặc TLS nội bộ, Trino yêu cầu một shared secret giống hệt nhau trên toàn bộ cluster. Không dùng secret của database hoặc object storage cho mục đích này.

Thêm property sau vào `etc/config.properties` trên coordinator và mọi worker; `TRINO_SHARED_SECRET` phải có cùng một giá trị ngẫu nhiên, dài trên mọi node.

```properties
internal-communication.shared-secret=${ENV:TRINO_SHARED_SECRET}
```

Nếu một worker nhận giá trị khác, nó không được xác thực và không đăng ký với coordinator. Khi rotate shared secret, cập nhật secret cho tất cả node rồi restart cả cluster trong một đợt bảo trì.

### 5. Kiểm tra và vận hành

1. Xác nhận hệ thống provision cấp đúng biến cho coordinator và các worker liên quan, không chỉ cho coordinator.
2. Khởi động hoặc restart Trino, rồi kiểm tra log để xác nhận catalog đã nạp thành công.
3. Kiểm tra Web UI có đủ số worker `ACTIVE` dự kiến sau khi đặt shared secret.
4. Chạy một truy vấn đọc nhỏ tới từng catalog cần credential; với object storage, kiểm tra cả thao tác ghi/xóa trên location thử nghiệm nếu quyền cho phép.
5. Rotate ngay các secret đã từng xuất hiện trong Git, log, image hoặc kênh chia sẻ; xóa giá trị hiện tại khỏi history Git nếu chính sách bảo mật yêu cầu.

Checklist:

- [ ] Properties chỉ chứa `${ENV:...}`, không chứa password/key/secret thật.
- [ ] Secret được cấp cho đúng tiến trình và node nạp property đó.
- [ ] `TRINO_SHARED_SECRET` giống nhau trên coordinator và mọi worker.
- [ ] Static S3 key được thay bằng IAM role/default credential chain khi môi trường hỗ trợ.
- [ ] Rotation, quyền truy cập và kiểm tra sau thay đổi đã được thực hiện.

## References

- [Trino — Security overview](https://trino.io/docs/current/security/overview.html)
- [Trino — TLS and HTTPS](https://trino.io/docs/current/security/tls.html)
- [Trino — Secure internal communication](https://trino.io/docs/current/security/internal-communication.html)
- [Trino — Secrets](https://trino.io/docs/current/security/secrets.html)
- [Trino — System access control](https://trino.io/docs/current/security/built-in-system-access-control.html)
- [mkcert](https://github.com/FiloSottile/mkcert)
- [Trino — Password file authentication](https://trino.io/docs/current/security/password-file.html)
- [Trino — LDAP authentication](https://trino.io/docs/current/security/ldap.html)
- [Trino — User mapping](https://trino.io/docs/current/security/user-mapping.html)
- [Trino — File-based access control](https://trino.io/docs/current/security/file-system-access-control.html)
- [Trino — Group mapping](https://trino.io/docs/current/security/group-mapping.html)
- [Trino — System access control](https://trino.io/docs/current/security/system-access-control.html)
- [Trino — Group provider](https://trino.io/docs/current/security/group-provider.html)
- [Trino — S3 file system support](https://trino.io/docs/current/object-storage/file-system-s3.html)
