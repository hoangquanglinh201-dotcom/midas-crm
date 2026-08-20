# Midas CRM — Supabase Setup Guide

Tài liệu này hướng dẫn kết nối `midas-crm.html` với Supabase PostgreSQL để nhiều máy/nhiều thiết bị dùng chung một database, thay cho `localStorage` cũ (chỉ lưu trên 1 trình duyệt).

Toàn bộ UI/UX/tính năng giữ nguyên 100%. Chỉ có tầng lưu trữ dữ liệu (`loadState()` / `saveState()`) được thay thế.

---

## A. SOURCE AUDIT (trước khi sửa)

```
Data source:      1 file HTML duy nhất (midas-crm.html), toàn bộ CSS + JS inline
Data storage:     localStorage, key "midas_crm_data_v1", lưu 1 blob JSON duy nhất
Data loading:     loadState() đọc blob từ localStorage -> gán vào biến STATE
Data creation:    push trực tiếp vào mảng STATE.xxx, rồi gọi saveState()
Data update:      Object.assign(record, payload), rồi gọi saveState()
Data deletion:    STATE.xxx = STATE.xxx.filter(...), rồi gọi saveState()
Data sample:      seedData() — 5 khách hàng, 7 deal, activities, nextActions, meetings mẫu
Main files:       midas-crm.html (không có package.json / build step / thư mục con)
Main functions:   loadState, saveState, saveCustomer, confirmDeleteCustomer, saveDeal,
                   confirmDeleteDeal, addActivity, addStatusUpdate, addDealNote,
                   addDealDocument, deleteDealDocument, addNextActionForCustomer,
                   toggleNextActionDone(Global), deleteNextAction, saveMeeting,
                   confirmDeleteMeeting, runBulkImport, handleImportFile
```

Toàn bộ app dùng **1 object `STATE`** duy nhất `{ customers, deals, activities, nextActions, meetings }`, luôn được ghi đè hoàn toàn xuống `localStorage` mỗi lần thay đổi (kể cả tính năng Import JSON trong Settings vốn đã ghi đè toàn bộ STATE). Vì vậy cách migrate ít rủi ro nhất là **giữ nguyên STATE làm nguồn dữ liệu render UI**, chỉ đổi 2 hàm `loadState()`/`saveState()` để đọc/ghi Supabase thay vì localStorage — không đụng tới ~15 hàm CRUD phía trên vì tất cả đều gọi chung `saveState()`.

---

## B. DATABASE — SQL SCHEMA

File đầy đủ: `schema.sql`. Gồm 5 bảng nghiệp vụ tương ứng đúng 5 mảng trong STATE, cộng bảng `profiles` chuẩn bị sẵn cho Phase 2 (chưa dùng):

```
customers      — khách hàng
deals          — deal/dự án (cột documents jsonb lưu tài liệu đính kèm, giữ đúng cấu trúc lồng cũ)
activities     — timeline hoạt động / cập nhật tình trạng / ghi chú deal
next_actions   — việc cần làm tiếp theo
meetings       — lịch hẹn
profiles       — (Phase 2, chưa dùng) map với auth.users
```

`id` dùng kiểu `text` (không phải `uuid`) vì app tạo id ở client bằng hàm `uid()` (dạng `id_xxxxx`), giữ nguyên để không phải đổi logic tạo id ở hàng chục nơi trong code.

Chạy toàn bộ `schema.sql` trong **Supabase Dashboard > SQL Editor**.

---

## C. FILE CHANGES

```
Created:
  schema.sql          - SQL schema đầy đủ (bảng, index, RLS policy)
  .env.example         - placeholder tên biến môi trường
  SUPABASE_SETUP.md    - tài liệu này

Modified:
  midas-crm.html
    - <head>: thêm 1 dòng <script> CDN @supabase/supabase-js
    - Thêm block "Supabase config" + supabaseClient + các hàm map
      customerToRow/rowToCustomer, dealToRow/rowToDeal, activityToRow/rowToActivity,
      nextActionToRow/rowToNextAction, meetingToRow/rowToMeeting, syncTable()
    - loadState(): chuyển thành async, đọc 5 bảng Supabase thay vì localStorage
      (fallback về localStorage nếu Supabase chưa cấu hình, để vẫn chạy được khi dev/test local)
    - saveState(): chuyển thành async, upsert + xoá record thừa trên cả 5 bảng
      theo thứ tự customers -> deals -> (activities, next_actions, meetings)
      để không vi phạm foreign key
    - Khối init cuối file: gói trong initApp() (async), hiện "Đang tải dữ liệu…"
      trong lúc chờ Supabase, chỉ seed dữ liệu mẫu nếu database thực sự trống hoàn toàn
    - Toàn bộ ~15 hàm CRUD khác (saveCustomer, saveDeal, addActivity,
      addNextActionForCustomer, saveMeeting, v.v.) KHÔNG bị đụng tới — vẫn gọi
      saveState() y hệt như cũ

Deleted:
  (không có)
```

Không có file nào khác bị đổi tên/xoá. UI, CSS, layout, icon, sidebar, modal... giữ nguyên 100%.

---

## D. DATA MIGRATION (dữ liệu mẫu / dữ liệu cũ trong trình duyệt)

- **Dữ liệu mẫu (`seedData()`)**: không cần migrate thủ công. Lần đầu tiên app kết nối một Supabase project trống (chưa có customer/deal/activity/next_action/meeting nào), `initApp()` sẽ tự seed 5 khách hàng mẫu y như trước, rồi đẩy lên Supabase.
- **Dữ liệu thật đang có trong localStorage của máy Leon (nếu có)**: dùng đúng tính năng **Export JSON** có sẵn trong Settings (nút "Xuất JSON backup") ở bản CRM cũ (chưa nối Supabase) để tải file backup, sau đó mở bản CRM mới (đã nối Supabase) và dùng **Import dữ liệu (JSON)** trong Settings để nạp lại — tính năng import vốn đã "ghi đè toàn bộ STATE rồi saveState()", nên sẽ tự động đẩy toàn bộ dữ liệu cũ lên Supabase mà không cần viết thêm script.

```
Source sample data:     seedData() trong midas-crm.html
Destination table:      customers, deals, activities, next_actions, meetings
Field mapping:          xem các hàm ...ToRow()/rowTo...() trong file — map 1-1
                         camelCase (STATE) <-> snake_case (Postgres)
Migration method:       tự động qua saveState() (upsert), hoặc qua tính năng
                         Export/Import JSON có sẵn nếu cần chuyển dữ liệu thật
```

---

## E. ENVIRONMENT VARIABLES

```
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY   (tên tương thích cũ: SUPABASE_ANON_KEY)
```

Không in giá trị thật ở đây. Không commit `.env`, `.env.local`, `.env.production` lên GitHub — chỉ commit `.env.example` với placeholder.

Vì `midas-crm.html` là 1 file tĩnh không có build step, có 2 cách đưa 2 giá trị trên vào app **mà không commit secret lên GitHub**:

**Cách 1 — khuyến nghị, không sửa file mỗi lần đổi key: Netlify Snippet Injection**
1. Netlify Dashboard > site > **Site configuration > Build & deploy > Post processing > Snippet injection**
2. Thêm đoạn sau vào **"Before `</head>` tag"**:
   ```html
   <script>
     window.MIDAS_SUPABASE_URL = "GIÁ_TRỊ_THẬT_TỪ_SUPABASE";
     window.MIDAS_SUPABASE_ANON_KEY = "GIÁ_TRỊ_THẬT_TỪ_SUPABASE";
   </script>
   ```
3. Giá trị nhập trực tiếp trong ô cấu hình Netlify (không nằm trong repo Git).

**Cách 2 — đơn giản nhất, đúng thói quen "1 file duy nhất" đang dùng**
Mở `midas-crm.html`, sửa trực tiếp 2 dòng:
```js
const SUPABASE_URL = window.MIDAS_SUPABASE_URL || 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = window.MIDAS_SUPABASE_ANON_KEY || 'YOUR_SUPABASE_ANON_KEY';
```
thành giá trị thật, rồi deploy. Anon/publishable key **không phải secret key** — Supabase thiết kế để lộ ở frontend, bảo mật thật sự nằm ở RLS policy trong `schema.sql`. Cách này chấp nhận được cho 1 CRM nội bộ, không public repo.

Không dùng `service_role` / secret key ở cả 2 cách trên.

---

## F. DEPLOYMENT — GitHub → Netlify → Supabase

1. **Supabase**: tạo project mới tại supabase.com > Project Settings > API, lấy `Project URL` và `anon public key`.
2. Vào **SQL Editor**, dán và chạy toàn bộ `schema.sql`.
3. Push `midas-crm.html`, `schema.sql`, `.env.example`, `SUPABASE_SETUP.md` lên GitHub repo hiện tại của Midas CRM (repo Netlify đang deploy).
4. Cấu hình 2 biến ở mục E (Cách 1 hoặc Cách 2).
5. Netlify: publish directory vẫn là thư mục gốc chứa `midas-crm.html`, build command giữ nguyên "không có" (static site) — không cần thêm gì vì không có build step.
6. Trigger deploy lại (Netlify auto-deploy khi push, hoặc "Trigger deploy" thủ công).
7. Mở lại CRM trên trình duyệt — nếu cấu hình đúng, mở DevTools Console sẽ **không** thấy dòng cảnh báo "Supabase chưa được cấu hình".

---

## G. SECURITY

- **RLS (Row Level Security)**: bật trên cả 5 bảng nghiệp vụ. Phase 1 dùng policy `for all using (true)` (cho phép anon key đọc/ghi mọi dòng), vì CRM chưa có đăng nhập và chỉ dùng nội bộ team Midas. Đây là đánh đổi có chủ đích, không phải sơ suất.
- **anon/publishable key**: an toàn để đặt trong code chạy ở trình duyệt — đây chính là mục đích thiết kế của key này. Nó **không** thể bỏ qua RLS.
- **secret key / service_role**: tuyệt đối không đưa vào file này hay bất kỳ file frontend nào. Không dùng trong dự án này ở giai đoạn hiện tại.
- **.env**: không commit; chỉ `.env.example` chứa placeholder được commit.
- **GitHub protection**: nếu repo public, ưu tiên Cách 1 (Netlify Snippet Injection) ở mục E thay vì hard-code trực tiếp trong file để tránh lộ URL/key trong lịch sử commit (dù bản thân 2 giá trị này không phải secret nhạy cảm).

---

## H. TEST RESULT

Đã kiểm tra ở mức code-level (đọc lại toàn bộ luồng CRUD, syntax JS hợp lệ):

```
Tested:
  - Cú pháp JavaScript hợp lệ (node --check) sau khi sửa
  - loadState()/saveState() không còn tham chiếu localStorage cho dữ liệu
    nghiệp vụ khi Supabase đã cấu hình
  - Toàn bộ các hàm CRUD hiện có (saveCustomer, saveDeal, addActivity,
    addDealDocument, saveMeeting, v.v.) không bị sửa đổi, vẫn gọi
    saveState() y như cũ -> hành vi UI không đổi

Not tested (CẦN Leon test thật sau khi deploy, xem mục "Test multi-device" dưới):
  - Test A-F end-to-end trên Supabase project thật + 2 thiết bị/trình duyệt thật
  - Hiệu năng khi dữ liệu lớn (hàng trăm+ khách hàng)
  - Hành vi khi mất mạng giữa chừng lúc đang lưu (đã có try/catch + toast lỗi,
    nhưng chưa test thực tế tình huống mất mạng)

Known issues:
  - saveState() hiện sync toàn bộ 5 bảng mỗi lần lưu (không chỉ record vừa đổi).
    Với quy mô CRM nội bộ (vài trăm record) không đáng lo, nhưng nếu dữ liệu
    lớn hơn nhiều thì nên tối ưu thành cập nhật theo từng bản ghi ở giai đoạn sau.
  - Nếu 2 người sửa cùng 1 khách hàng gần như cùng lúc, người lưu sau sẽ ghi
    đè người lưu trước (last-write-wins) — chưa có cơ chế khoá/merge xung đột.
  - Heuristic "chỉ seed dữ liệu mẫu nếu database trống hoàn toàn" nghĩa là nếu
    Leon xoá sạch toàn bộ 5 loại dữ liệu, lần load kế tiếp sẽ tự thêm lại 5
    khách hàng mẫu. Nếu không muốn vậy, xoá seedData() khỏi initApp() sau khi
    đã có dữ liệu thật.
```

**Bạn (Leon) cần tự chạy các test dưới đây sau khi deploy thật** — theo đúng yêu cầu "không claim thành công khi chưa test":

### Test A — Create
Máy A: thêm khách hàng mới. Máy B: F5 → khách hàng đó phải xuất hiện.

### Test B — Update
Máy A: sửa thông tin khách hàng. Máy B: F5 → thấy dữ liệu mới.

### Test C — Delete
Máy A: xoá khách hàng. Máy B: F5 → khách hàng biến mất.

### Test D — Deal
Máy A: tạo deal mới. Máy B: F5 → deal xuất hiện.

### Test E — Đóng/mở lại trình duyệt
Đóng hẳn trình duyệt trên 1 máy, mở lại CRM → dữ liệu vẫn còn.

### Test F — Trình duyệt khác
Mở CRM bằng Chrome, Edge, Safari trên cùng 1 máy → dữ liệu giống nhau ở cả 3.

---

## I. FUTURE ROADMAP

```
Phase 2: Supabase Auth
  - Bật Supabase Auth (email/password hoặc magic link)
  - Liên kết auth.users -> bảng profiles (đã tạo sẵn trong schema.sql)
  - Thêm màn hình đăng nhập đơn giản trước khi vào app

Phase 3: Role / Permission
  - profiles.role: admin / manager / staff
  - Sửa RLS policy theo role thay vì "for all using (true)"
  - Ví dụ: staff chỉ thấy khách hàng mình phụ trách (owner = tên mình)

Phase 4: Realtime
  - Bật Supabase Realtime cho 5 bảng nghiệp vụ (dòng comment sẵn cuối schema.sql)
  - Subscribe thay đổi -> tự render() lại UI khi có thiết bị khác vừa lưu,
    không cần F5 thủ công

Phase 5: Audit Log / Advanced CRM
  - Bảng audit_log ghi lại ai đổi gì, lúc nào
  - Tối ưu saveState() thành cập nhật theo record thay vì full-sync mỗi bảng
```
