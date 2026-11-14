# HaUI Form – CSDL Oracle cho hệ thống khảo sát trực tuyến

Bài tập lớn học phần Quản trị cơ sở dữ liệu nâng cao. Gồm script SQL/PLSQL cho Oracle Database 19c,
môi trường Docker và ứng dụng web minh họa.

## Chạy nhanh

Yêu cầu: Docker Desktop, cấp cho Docker tối thiểu 4 GB RAM.

```bash
docker compose up -d --build
docker compose logs -f oracle      # chờ tới khi thấy "DATABASE IS READY TO USE!" và container healthy
```

- Lần đầu mất khoảng 20–30 phút: tạo CDB `ORCLCDB` + PDB `ORCLPDB1`, bật ARCHIVELOG, chạy script 01 → 10.
- Web: <http://localhost:3000> (chọn người dùng ở góc trên bên phải; trang **Oracle Lab** chạy các kịch bản minh họa).
- Kết nối SQL Developer / SQL*Plus: `localhost:1521/ORCLPDB1`

| Tài khoản | Mật khẩu | Vai trò |
|---|---|---|
| `sys` (AS SYSDBA) | `Oracle19c#Pwd` | Quản trị (CDB `ORCLCDB`) |
| `hauiform` | `HaUIForm#2026` | Chủ schema, chạy script 02–08, 10–12, 14 |
| `hf_app` | `HfApp#2026` | Tài khoản ứng dụng web (chỉ SELECT + EXECUTE, chịu VPD) |
| `hf_report` | `BaoCao#2026` | Cán bộ báo cáo (profile khóa sau 3 lần sai mật khẩu) |

Đặt lại dữ liệu trước mỗi buổi minh họa: trang Oracle Lab → "Đặt lại dữ liệu minh họa", hoặc `EXEC pkg_demo.reset_all;`

## Cấu trúc

```
docker-compose.yml          Oracle 19c EE + web
docker/oracle/              dbca.rsp.tmpl (CDB+PDB), install_hauiform.sh, enable_archivelog.sh, backup.sh
sql/01 … 05                 Tablespace, bảng, chỉ mục, dữ liệu mẫu, kiểm tra ràng buộc
sql/06_plsql.sql            PKG_CTX, PKG_VPD, PKG_RESPONSE (nộp phản hồi), PKG_FORM, job
sql/07_trigger.sql          Trigger nghiệp vụ + nhật ký
sql/08_view.sql             View, materialized view
sql/09_bao_mat.sql   (SYS)  Profile, role, user, application context, VPD, Unified Auditing
sql/10_du_lieu_demo.sql     Sinh viên bổ sung, PKG_DEMO
sql/11_giao_dich.sql        Minh họa giao dịch, nộp trùng, khóa, mức cô lập
sql/12_flashback.sql        Flashback Query / Version Query / Table / Drop
sql/13_flashback_pdb.sql (SYS) Flashback PDB về restore point
sql/14_truy_van_minh_hoa.sql  Truy vấn minh họa trigger và view
web/                        Node.js + Express + node-oracledb (Thin)
docs/baocao/                Báo cáo
```

Sao lưu: `docker exec hauiform-oracle bash /opt/hauiform/docker/backup.sh` (RMAN + Data Pump).

Chạy web ngoài Docker: `cd web && npm install && DB_CONNECT=localhost:1521/ORCLPDB1 npm start`.
