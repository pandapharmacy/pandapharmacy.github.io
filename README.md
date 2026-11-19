# 熊貓藥局 Panda Pharmacy｜臺灣客人專屬訂購網頁

- 客人頁：`docs/index.html`
- 後台：`docs/admin.html`
- 資料庫：Supabase（`supabase/schema.sql`、`supabase/storage.sql`）

## 結構
| 位置 | 用途 |
|---|---|
| `src/` | 頁面原始檔（Store / Admin / Shared） |
| `build.py` | 併檔並填入 Supabase 網址與公開金鑰，輸出到 `docs/` |
| `docs/` | GitHub Pages 發布的網頁 |
| `supabase/schema.sql` | 資料表與所有後端函式（可重複執行） |
| `supabase/storage.sql` | 商品照片儲存空間 |
| `migrate.py` | 從舊 Google 試算表搬資料 |

## 發布
```
python3 build.py https://<project>.supabase.co <anon-key>
git add -A && git commit -m "update" && git push
```
GitHub Pages：Settings → Pages → Branch `main` / 資料夾 `/docs`。
