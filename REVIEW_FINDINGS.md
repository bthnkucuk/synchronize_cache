# Kod incelemesi bulguları — 2026-09-19

Kapsam: `packages/` altındaki 5 paket (`main` @ `ad04811`, Dart 3.13.3 / Flutter 3.47.3).
Yöntem: 5 paralel inceleme ajanı (salt-okunur) + en ciddi iddiaların elle doğrulanması.

**Durum işaretleri**

| İşaret | Anlamı |
|---|---|
| ✅ çalıştırıldı | Gerçek paket koduyla ya da birebir kopyasıyla çalıştırılıp yeniden üretildi |
| ✅ okundu | İlgili kod okunarak doğrulandı |
| 📋 ajan | Ajanın kendi kanıtıyla raporladığı; bağımsız olarak yeniden doğrulanmadı — düzeltmeden önce doğrula |

## Durum (2026-09-19; çekirdek ve REST 0.2.2, search_engine 0.2.1 — diğer paketler 0.2.0)

**Düzeltildi** (her biri kırmızı→yeşil regresyon testiyle + `todo_advanced` "Sync scenarios" ekranında
Playwright ile tarayıcıda önce FAIL, sonra PASS olarak kanıtlandı): **K1-1, K1-2, K1-3, K1-4, K1-6, K1-7(a,b)**.

Tarayıcı kanıtı — aynı altı senaryo, gerçek Dart Frog backend'e karşı:

| Senaryo | Düzeltme öncesi | Düzeltme sonrası |
|---|---|---|
| K1-1 | aynı op tek `sync()` içinde 29 kez push edildi (döngüyü senaryo sigortası durdurdu) | 9 ms'de 1 push; op sonraki sync için outbox'ta |
| K1-2 | `description="old server note"` (temizlenen alan geri geldi) | yerel ve sunucu `description=null`, sunucunun `priority=1` değişikliği korundu |
| K1-3 | `[2, 4, 8, 16]` | `[1, 1, 1, 1]` |
| K1-4 | `PUT …/a#b` → `…-a` kaynağı; `..` → `DELETE http://localhost:8080/` | `PUT …/a%23b` → `…-a#b`; `..` → istek yok, `PushError` |
| K1-6 | `health()` 6,0 sn bekledi (sunucu kadar) | 1,0 sn'de `false` (sınır 1 sn) |
| K1-7 | +03:00'te cursor `07:00Z` | `10:00Z` |

**Birleşti (PR #7, `main`):** **K1-10** + yan kazanımlar **K2-9** (rowid eşitlik bozucu), **K1-5** (motor düzeyinde: batch'te varlık başına tek op), **K2-12**'nin outbox kısmı (mikrosaniye), **P2**'nin büyük kısmı (op başına SELECT artık yalnızca ms hassasiyetli tabanlarda).
Tarayıcı kanıtı (K1-10 senaryosu, gerçek backend): eski kütüphane → *1 düzenlemede 1, iki hızlı düzenlemede 2 conflict*; yeni kütüphane → *0 ve 0*.

**Düzeltildi — 0.2.1 (`fix/tier1-rest-and-core-perf`)** — her biri kırmızı→yeşil testle:
**K1-7(c)**, **K1-8**, **K1-9**, **P1** (outbox indeksleri), **P2**'nin kalanı (web'de satır okuması yok), **P3** (batch başına tek transaction), **P10**, **P11**, **K2-5**, yeni **K2-41** (transport sonuç döndürmezse push döngüsü), e2e test sunucusunun sayfalama/istisna düzeltmeleri.

Tarayıcı kanıtı — aynı senaryo kodu, aynı backend; "önce" = `main` (`fd87f1d`) kütüphanesiyle derleme:

| Senaryo | Düzeltme öncesi | Düzeltme sonrası |
|---|---|---|
| K1-7c | 1 liste isteği, token izlenmedi, sunucudaki 2 satırdan 0'ı geldi | 2 istek, token izlendi, 2/2 satır |
| K1-8 | `409 {"error":"conflict"}` → conflicts=1, resolved=1, **1 zorla üzerine yazma** (`X-Force-Update`), op kuyruktan çıktı | conflicts=0, errors=1, zorla yazma yok, op kuyrukta; sonraki sync'te teslim |
| P1 (senaryo) | indeks yok; 3 outbox sorgusunun 3'ü `SCAN` (+ `TEMP B-TREE`); 5000 op'ta take 1,17 / 0,97 ms | 3 indeks (indeksleri silinmiş DB'de ilk sync'te oluştu); 0 sorgu indekssiz; take 0,72 / 0,57 ms |
| P3 (senaryo) | 25 op'luk batch'te **52 ayrı commit**, 0 transaction | **1 transaction**, 0 tekil commit |

P1 ölçümü (yerel SQLite, 20 000 op, ~1 KB payload): tek kind take 9,44 → 0,09 ms · filtresiz take 8,69 → 0,12 ms · rebase 6,30 → 0,16 ms. Tarayıcıda (wasm, 5000 op) fark küçük çünkü süreyi tarama değil worker gidiş-dönüşü ve commit belirliyor; asıl kazanç kuyruk büyüdükçe ortaya çıkan N² davranışının kalkması.
Ajanın "`watchOutboxCount` her seferinde tam tarama" iddiası **ölçümle yanlış çıktı**: filtresiz `COUNT(*)` PK oto-indeksini kullanıyor (20 000 satırda 0,19 ms). `(tryCount)` indeksi eklenmedi: `countStuck` sync başına kind başına bir kez çalışıyor (doğrusal), batch/op başına değil.

**İncelemede (`fix/outbox-retry-budget-cursor-tombstones`, 0.2.2)** — bağımsız rakip incelemesinin (bkz. `COMPETITIVE_ANALYSIS.md`, yerel) doğrulanan bulguları; her biri kırmızı→yeşil testle:
**K1-11** (çevrimdışı kalmak kuyruğu kalıcı park ediyordu), **K2-42** (REST push hataları durum kodunu kaybediyordu), **K2-43** (`todo_advanced` backend'i tombstone yaymıyordu + doküman tersini söylüyordu), **K2-44** (cursor ms'e kırpılıyordu), **K2-45** (1973 öncesi damgalar yanlış okunuyordu), **K2-46** (ağ yokken batch'in her op'u ayrı ayrı deneniyordu).

| Senaryo (tarayıcı, gerçek backend) | Düzeltme öncesi | Düzeltme sonrası |
|---|---|---|
| K1-11 · 6 sync ağ yok + 6 sync `401`, sonra sağlıklı sync | sayılan deneme **5**, stuck=1; ağ isteği 5'te kesildi; sağlıklı sync'te pushed=0, yazma sunucuya **hiç ulaşmadı** | sayılan deneme 0, stuck=0; ilk sağlıklı sync'te pushed=1 |
| K2-43 · başka istemci todo'yu siliyor, sonra pull | pull 0 satır; yerel `deletedAt=null`, uygulama göstermeye devam ediyor | pull 1 satır (tombstone); `deletedAt` dolu, uygulama göstermiyor |

K2-44 için tarayıcı senaryosu yok: tarayıcıda `DateTime` zaten ms hassasiyetinde, etki yalnızca native'de (motor testi: değişiklik yokken ikinci pull **2** satırı yeniden indiriyordu → 0).

**Açık kalanlar:** Kademe 2 / Kademe 3'ün geri kalanı; aşağıdaki "Yeni açık maddeler".

Efor: S (< yarım gün) · M (1–2 gün) · L (daha uzun / tasarım kararı gerekir).
Satır numaraları `ad04811` içindir.

---

## Kademe 1 — Veri kaybı / askıda kalma

### K1-1 · `pushAll` çözülemeyen conflict'te sonsuz döngüye giriyor — ✅ çalıştırıldı · S · ✔ DÜZELTİLDİ (0.2.0)
- **Yer:** `packages/offline_first_sync_drift/lib/src/services/push_service.dart:75-192`
- **Mekanizma:** `while (true)` yalnızca outbox boşalınca ya da `hadPushErrors` (sadece `PushError`'da set edilir) ile kırılıyor. `PushConflict` alıp `resolve()`'dan `resolved: false` dönen bir op, `skipConflictingOps == false` (varsayılan) iken ne `ack`'leniyor ne de `tryCount`'u artıyor (`recordFailures` yalnızca `PushError` için çağrılıyor; `ConflictService` outbox'a hiç dokunmuyor). Sonraki `take()` aynı op'u döndürüyor → aynı conflict → sonsuz.
- **Erişilebilirlik:** `ConflictStrategy.manual` + resolver yok (`DeferResolution`), ya da `autoPreserve`/`merge`'de `forcePush`'un sürekli conflict/hata dönmesi.
- **Kanıt:** Transport hep `PushConflict`, stub `resolved: false` → 50 push çağrısı (50.'de test zorla kırdı), `resolve` 49 kez, op hâlâ outbox'ta. `test/unit/push_service_test.dart:412-415`'teki yorum riski zaten kabul ediyor ("without risking an infinite loop in the test").
- **Düzeltme:** Batch'te çözülemeyen conflict kaldıysa döngüyü kır (mevcut "Do not spin on the same failed operations" politikasıyla aynı). Ayrı karar: çözülemeyen conflict `tryCount`'a sayılsın mı (5 denemeden sonra "stuck" olur) yoksa her sync'te bir kez mi denensin? `resolve()` çağrısını `try/catch`'e al — fırlatan bir `conflictResolver` şu an tüm `pushAll`'u düşürüyor.
- **Not:** `'unresolved conflict without skipConflictingOps gets resolved on retry'` testi eski davranışı (aynı `pushAll` içinde hemen yeniden push) sabitliyor; güncellenmesi gerekir.

### K1-2 · `preservingMerge` bilerek temizlenen alanı geri getiriyor — ✅ çalıştırıldı · S · ✔ DÜZELTİLDİ (0.2.0)
- **Yer:** `packages/offline_first_sync_drift/lib/src/conflict_resolution.dart:281-284`
- **Mekanizma:** `changedFields` kapısından geçtikten (yani alan kullanıcı tarafından değiştirilmiş olarak işaretlendikten) sonra `localVal == null && serverVal != null` → `continue` (sunucu değeri kalır). `autoPreserve` varsayılan strateji; olay yayınlanmıyor.
- **Kanıt:** `local={note: null, title: 'mine'}`, `server={note: 'old server note', title: 'theirs'}`, `changedFields={note, title}` → `note='old server note'`, `title='mine'`.
- **Düzeltme:** `changedFields != null && local.containsKey(key)` iken `null`'ı açık temizleme say (`result[key] = null`). `containsKey` şartı, kısmi payload'da eksik anahtarı "temizlendi" sanmamak için. `changedFields == null` iken mevcut davranış korunur. Aynı örüntü opt-in `defaultMerge`'de de var (`:199-206`).
- **Kırıcı mı:** İmza değil, davranış değişikliği.

### K1-3 · `_mergeLists` `id`'siz map listelerini her conflict'te ikiye katlıyor — ✅ çalıştırıldı · S · ✔ DÜZELTİLDİ (0.2.0)
- **Yer:** `packages/offline_first_sync_drift/lib/src/conflict_resolution.dart:326-329`
- **Mekanizma:** `id` anahtarı olmayan öğeler için `server.contains(item)` kullanılıyor; `Map` için `==` kimlik karşılaştırmasıdır → içerikçe eşit map'ler "farklı" sayılıp ekleniyor. Sonuç force-push ediliyor ve yerele yazılıyor.
- **Kanıt:** `tags: [{a: 1}]` iki tarafta da aynı → 4 merge turunda liste boyu 2, 4, 8, 16.
- **Düzeltme:** Derin eşitlikle karşılaştır (`ChangedFieldsDiff._deepEquals` paylaşılan iç yardımcıya taşınabilir). Yan öneri: yalnızca `'id'` değil `SyncFields.idFields`; O(n·m) `server.any` yerine id `Set`'i.

### K1-4 · REST URL'inde kimlikler kodlanmıyor — ✅ çalıştırıldı · S · ✔ DÜZELTİLDİ (0.2.0)
- **Yer:** `packages/offline_first_sync_drift_rest/lib/src/rest_transport.dart:87-89` (kullanım: `:356`, `:386`, `:523`)
- **Mekanizma:** `Uri.parse('$base/$kind/$id')` — id ham olarak yola gömülüyor.
- **Kanıt:** `a#b` → `/todos/a#b` (fragment gönderilmez → **yanlış varlık**), `a?b` → `/todos/a?b`, `a/b` → başka rota, `..` → `https://api.example.com/v1/` (**koleksiyon köküne DELETE/PUT**). Boşluk ve Unicode doğru kodlanıyor; UUID kimlikler güvende.
- **Düzeltme:** id'yi `pathSegments` ile tek segment olarak kodla; `.`/`..`/boş id'yi istek göndermeden `PushError` ile reddet (nokta segmentleri yüzde-kodlamayla güvenli hâle gelmez). Bonus: sorgu içeren `base` (`…/v1?tenant=1`) şu an bozuk URL üretiyor.

### K1-5 · `pushConcurrency > 1` iken aynı varlığın op'ları eşzamanlı gidiyor — ✅ okundu · M · motor düzeyinde giderildi (0.2.0); doğrudan `transport.push` çağıranlar için hâlâ geçerli
- **Yer:** `packages/offline_first_sync_drift_rest/lib/src/rest_transport.dart:168-183`
- **Mekanizma:** Chunk başına `Future.wait`; varlık anahtarına bakılmıyor. Outbox PK'sı yalnızca `opId`, her düzenleme yeni `OpId.v4()` alıyor → aynı `(kind,id)` için birden çok op bir arada bulunabiliyor. `PUT` + `DELETE` aynı chunk'ta yarışırsa DELETE önce biterse PUT satırı diriltiyor; ikisi de başarı sayılıp ack'leniyor → yalnızca tam resync onarır.
- **Düzeltme:** Varlık anahtarlı (`'$kind\u0000$id'`) sınırlı worker havuzu: aynı varlığın op'ları sıralı, farklı varlıklar paralel. P9'u da çözer. `test/e2e/parallel_push_test.dart` 10 *farklı* varlık kullandığı için bu senaryo testsiz.
- **Sahibine soru:** Production'da `pushConcurrency > 1` kullanan var mı?

### K1-6 · Hiçbir yerde istek timeout'u yok — ✅ okundu · S · ✔ DÜZELTİLDİ (0.2.0)
- **Yer:** `rest_transport.dart:129, 371-376, 406-409, 525, 614`; `grep timeout packages/*/lib` → boş. `SyncConfig`'te de alan yok.
- **Mekanizma:** Yarı açık soket (captive portal, NAT düşmesi, arka plana alınan uygulama) `pull`/`push`/`health`'i sonsuza dek asıyor; istisna oluşmadığı için `_withRetry` devreye girmiyor, `SyncEngine.sync()` dönmüyor.
- **Düzeltme:** `Duration requestTimeout = const Duration(seconds: 30)` (opsiyonel ctor parametresi); gönderim **ve gövde okuması** birlikte sarılmalı. `TimeoutException` `_withRetry`'ın catch'ine düşer ve yeniden denenir.

### K1-7 · Pull cursor: dilimsiz zaman damgası yerel saat sayılıyor; eksik id `"null"` oluyor — ✅ çalıştırıldı · S · ✔ (a) ve (b) DÜZELTİLDİ (0.2.0); ✔ (c) DÜZELTİLDİ (0.2.1)
- **Yer:** `packages/offline_first_sync_drift/lib/src/services/pull_service.dart:95-112`
- **Mekanizma:** (a) `DateTime.parse(ts.toString()).toUtc()` — `Z`/ofset içermeyen ISO dizgisi yerel saat olarak ayrıştırılıp kaydırılıyor. (b) `(last['id'] ?? last['ID'] ?? last['uuid']).toString()` — id yoksa cursor'a literal `"null"` yazılıyor (hemen altındaki `updatedAt` kontrolü ise doğru şekilde `ParseException` atıyor). (c) 📋 `if (page.items.isEmpty) break;` (`:68`), `token = page.nextPageToken`'dan (`:125`) önce çalışıyor → boş ama devamı olan sayfa pull'u erken bitiriyor.
- **Kanıt:** `'2024-01-01T10:00:00.000'` → İstanbul: `07:00Z` (cursor geride → zararsız yeniden çekme); New York: `15:00Z` (cursor **ileride** → aradaki kayıtlar 7 günlük tam resync'e kadar atlanır); `Z` ekiyle sorun yok.
- **Düzeltme:** Ortak `parseServerTimestamp` (dilimsiz girdiyi UTC say); id yoksa `ParseException`. Aynı ayrıştırma örüntüsü `conflict_resolution.dart:341` ve `syncable_table.dart:80-81`'de de var.
- **Bilerek dokunulmayanlar:** `SyncableTable.updatedAtOf` (`syncable_table.dart:80`) değeri **yerel** uygulamanın `toJson`'undan alır; orada dilimsiz bir dizgi gerçekten yerel saati temsil eder ve mevcut `.toUtc()` doğrudur — ajanın "aynı düzeltmeyi uygula" önerisi burada yanlış olurdu. `ConflictUtils.extractTimestamp` hem yerel hem sunucu verisine uygulanabildiği için belirsiz → sahip kararı.
- **Not:** Örnek uygulamada "id'siz öğe" kısmı gösterilemiyor (`Todo.fromJson` eksik id'de zaten fırlatıyor); o kısım paket birim testiyle (`pull_service_test.dart`) kapsanıyor.
- **Sahibine soru:** Sunucularınız `Z` ekli mi gönderiyor? (Dart'ın `toIso8601String()`'i UTC için ekler.)

### K1-8 · Kullanışsız gövdeli 409, `serverData: {}` + `serverTimestamp: now()` uyduruyor — ✅ çalıştırıldı · S · ✔ DÜZELTİLDİ (0.2.1)
- **Uygulanan:** Kayıt taşımayan 409 (boş gövde, JSON olmayan gövde, dizi, hata zarfı, boş `current`) → `PushError(TransportException 409)`; batch yanıtındaki 409'lar dahil. "Kayıt" = dolu `current`/`serverData` nesnesi ya da id / `updatedAt` alanı taşıyan gövde. Zaman damgası **şart koşulmadı**: mevcut testlerin 6'sı damgasız `current` kullanıyor (ilk denemede kırıldılar); damga yoksa `now()`. Tarayıcıda varsayılan `autoPreserve` ile eski davranış: uydurma conflict "çözülüp" `X-Force-Update` ile sunucunun sürüm kontrolü atlanarak yazılıyordu.
- **Yer:** `rest_transport.dart:454-466`, `:468-504`
- **Mekanizma:** Boş gövdeli 409 (ör. reverse proxy) → `PushConflict(serverData: {}, serverTimestamp: DateTime.now())`. `now()` sunucuyu koşulsuz "daha yeni" yapıyor; `lastWriteWins` → `AcceptServer` → `fromJson({})` sağlam yerel satırın üzerine boş varlık yazıyor (ya da fırlatıyor). `?? body` dalında `{"error": "version mismatch"}` zarfı varlık payload'ı sayılıyor.
- **Düzeltme:** `current`/`serverData` ve ayrıştırılabilir zaman damgası yoksa `PushError(TransportException.httpError(409, body))` döndür.

### K1-9 · `SearchTransport` normalizer'ı sorguya uygulamıyor — ✅ çalıştırıldı · S · ✔ DÜZELTİLDİ (0.2.1)
- **Uygulanan:** `DriftFtsSearchTransport(db, normalizer: …)`; `SearchEngine` ikisinin birlikte verilip verilmediğini `assert` ediyor. Kanıt `test/e2e/search_pipeline_test.dart` (`ışık`/`IŞIK`/`İstanbul`/`calisma`, `watchSearch`). Örnek uygulamada arama olmadığı için tarayıcı senaryosu yok.
- **Yer:** `packages/search_engine/lib/src/transport/search_transport.dart:26-45`, `drift_fts_search_transport.dart:25-56`, `search_engine.dart:57-64`
- **Mekanizma:** `SearchEngine` yazarken normalize ediyor ama `SearchTransport.search`/`watchSearch`'te `normalizer` parametresi yok → `_db.searchGlobal(...)` onsuz çağrılıyor. Trigram tokenizer `I`→`ı` ve `İ`→`i` katlamasını yapmıyor; Türkçe eşleşmenin tamamı normalize kolonlara dayanıyor.
- **Kanıt (SQLite 3.54 FTS5):** `title='Işık Raporu'`, `title_normalized='isik raporu'`; `MATCH '"ışık"*'` → 0 satır; normalize dalıyla → 1 satır.
- **Düzeltme:** Normalizer'ı `DriftFtsSearchTransport` constructor'ına ver (soyut metoda parametre eklemek dış implementer'ları kırar).
- **Sahibine soru:** Uygulama `transport.search` mü, yoksa doğrudan `searchGlobal(normalizer:)` mi çağırıyor? İkincisiyse bu canlı bug değil, yayın öncesi tuzak.

### K1-10 · (YENİ) Sunucuda değişiklik yokken de her düzenleme conflict üretiyor — ✅ çalıştırıldı · M · ✔ DÜZELTİLDİ (0.2.0)
- **Yer:** `packages/offline_first_sync_drift/lib/src/services/push_service.dart` — `_reStampBaseUpdatedAt` / `_readLocalUpdatedAt`; tetikleyen kullanım: `example/todo_advanced/frontend/lib/repositories/todo_repository.dart` (`updatedAt: now`).
- **Mekanizma:** Writer op'a doğru tabanı koyuyor (`baseUpdatedAt: todo.updatedAt` = sunucunun bildiği sürüm). Push'tan hemen önce `_reStampBaseUpdatedAt` bu değeri **yerel satırın** `updatedAt`'iyle eziyor. Uygulama düzenlemede `updatedAt`'i yerelde artırıyorsa (örnek uygulama artırıyor; doğal bir kullanım) taban = yerel "şimdi" ≠ sunucunun `updated_at`'i → tam eşleşme isteyen sunucu 409 döndürüyor.
- **Kanıt (geçici e2e testi, gerçek backend):** oluştur → sync → yalnızca yerelde `title` düzenle → sync ⇒ `conflictDialog=true, conflicts=1, pushed=0`. Sunucu tarafında hiçbir değişiklik yapılmadı.
- **Etki:** `ConflictStrategy.manual`'de kullanıcı **her** düzenlemede conflict diyaloğu görür. Varsayılan `autoPreserve`'de conflict gizlice merge + force-push ile çözülür: her düzenleme için fazladan 409 + force-push turu ve gerçek conflict tespitinin anlamsızlaşması.
- **Uygulanan çözüm:** sunucu sürümü artık yerel `updatedAt` kolonundan tahmin edilmiyor, push yolunda açıkça zincirleniyor. (1) Batch'te varlık başına tek op (en eskisi); (2) başarılı push ya da çözülen conflict sonrası sunucunun döndürdüğü satırın `updated_at`'i o varlığın kuyruktaki op'larının tabanına yazılıyor (`rebaseOutboxOps`); (3) koşulsuz yeniden damgalama kaldırıldı — verilen `baseUpdatedAt` yeniden belirleyici; yerel satır yalnızca *aynı sürümün* kaybolan mikrosaniyesini geri almak için kullanılıyor; (4) outbox tabanı mikrosaniye saklıyor (şema değişikliği yok; eski ms satırları büyüklükten ayırt edilip okunuyor); (5) force-push sonrası yerele sunucunun döndürdüğü satır yazılıyor.
- **Ek kazanç:** eski yeniden damgalama, araya giren bir pull yerel satıra başka istemcinin sürümünü yazdığında gerçek conflict'i **yutuyordu** (kuyruktaki düzenleme o yazıyı sessizce eziyordu). Yeni testlerden biri tam bunu sabitliyor ve eski kodda kırılıyor.
- **Neden diğer seçenekler değil:** ayrı sunucu-sürümü kolonu tüm tüketicilere şema göçü dayatırdı; "yerelde `updatedAt`'i değiştirmeyin" kuralı ise doğal bir kullanımı yasaklayıp kırılganlığı kütüphanede bırakırdı.
- **Dikkat (tup):** #4'ten beri parametre fiilen "danışma" niteliğindeydi; artık **düzenleme öncesi** varlığın `updatedAt`'i verilmeli. Güncelleme anında kuyrukta bayat tabanlı op varsa bir kerelik conflict olabilir.
- **Testler:** `test/server_version_chain_test.dart` (belgelenen protokolü birebir uygulayan, mikrosaniyeli sahte sunucu; 10 testin 8'i eski kodda kırılıyor), `test/unit/outbox_base_version_test.dart`; uyarlanan Round 2 grubu — "happy path" artık `pageSize: 1` zorlaması olmadan geçiyor (eski kodda varsayılan sayfa boyutuyla kırılıyor).

### Örnek uygulamada (todo_advanced) bulunanlar
- ✔ Düzeltildi: backend CORS izin listesinde `Authorization` yoktu → tarayıcıdaki **her** istek preflight'ta düşüyordu (örnek web'de hiç çalışmamış).
- ✔ Düzeltildi: `TodoRepository` değişen alanı `'dueDate'` olarak işaretliyordu; `changedFields` snake_case JSON anahtarlarıyla (`'due_date'`) eşleştirildiği için bitiş tarihi değişiklikleri merge'de yok sayılıyordu.
- ✔ Düzeltildi (0.2.0): frontend'de `build.yaml` yoktu → drift `DateTime`'ı **unix saniyesi** olarak saklıyor, sunucunun `updated_at`'i kırpılıyor, uygulama kırpılmış değeri taban diye geri gönderiyor → her zincirin ilk düzenlemesi 409. `store_date_time_values_as_text: true` + şema v2 göçü (testli) eklendi. README'ye bunun **zorunlu** olduğu yazıldı.
- ✔ Düzeltildi (0.2.0): backend sürümleri mikrosaniyeyle üretiyordu; tarayıcı (`Date`) yalnızca milisaniye tutabildiği için hiçbir web istemcisi sürümü geri gönderemiyordu. `serverNow()` ile milisaniyeye indirildi; protokol dokümanına hassasiyet notu eklendi.
- Açık: `Todo.copyWith` `description ?? this.description` yazdığı için nullable alanları **temizleyemiyor** (repository yine de alanı "değişti" diye işaretliyor). `ConflictHandler`'daki alan adı listesi de `'dueDate'` kullanıyor (`conflict_handler.dart:239`).
- Not: transport boş token'da bile `Authorization: ''` header'ı gönderiyor (gereksiz preflight + özensiz).

### K1-11 · (YENİ) Çevrimdışı kalmak kuyruğun tamamını kalıcı olarak "stuck" yapıyor — ✅ çalıştırıldı · S–M · ✔ DÜZELTİLDİ (0.2.2)
- **Yer:** `push_service.dart` (`pushAll` → `fail`), `sync_database.dart` (`recordOutboxFailures`, `takeOutbox(maxTryCountExclusive)`), `sync_error.dart`.
- **Mekanizma:** `maxOutboxTryCount` (varsayılan 5) **her** başarısız push'u sayıyordu. `RestTransport` tek-op modunda ağ yokken her op için `PushError(NetworkException)` döndürür → `tryCount`+1. Ağsız 5 sync denemesinden sonra (`startAuto` varsayılanıyla 25 dk) kuyruktaki **bütün** yazmalar `take()`'ten kalıcı olarak çıkıyor; bağlantı gelince de gönderilmiyor. Süresi dolmuş token (`401`) ve sunucu kesintisi (`5xx`) aynı sonucu veriyor. Uygulama `retryStuckOperations()`'ı bilmiyorsa veri sessizce hiç senkronlanmıyor — özellik dokümanlarda da hiç geçmiyordu.
- **Kanıt:** Birim probu: 6 başarısız sync + sağlıklı sync → `pushed=0, stuck=1` (ağ / 401 / 503 üçünde de). Tarayıcıda gerçek backend'le: yukarıdaki tablo.
- **Düzeltme:** Bütçe yalnızca op'la ilgili hatalarda tükeniyor (`401/403/408/425/429` dışındaki `4xx`, durum kodu olmayan hata). Ağ, zaman aşımı, `401/403`, `408/425/429`, `5xx` sayılmıyor ama raporlanıyor (`OperationFailedEvent(willRetry: true)`, `SyncStats.errors`, `sync_outbox_meta.last_error`). Yeni public API: `SyncErrorInfo.isEnvironmental`, `recordOutboxFailures(countAttempts:)`. `403`'ü "çevresel" saymak bilinçli: birçok backend süresi dolmuş oturuma 403 döner; yanlış sınıflamanın bedeli bir yanda op başına sync başına 1 fazladan istek, diğer yanda sessiz veri kaybı.
- **Yükseltme notu:** Eski davranışla park edilmiş op'lar park kalır → uygulama bir kez `retryStuckOperations()` çağırmalı (CHANGELOG'da). Otomatik iyileştirme (`last_error` metninden tanıyıp sıfırlamak) kırılgan bulunduğu için yapılmadı — **sahip kararı**.

### Yeni açık maddeler (2026-09-19 akşamı)
- **`final class` API kırılması (PR #5 ile main'de):** uyarı temizliği sırasında 0.1.2'de düz `class` olan public sınıflar `final class` oldu — `PushService`, `PullService`, `OutboxService`, `CursorService`, `ConflictResolutionResult`, `NetworkSyncHandler`, `DriftFtsSearchTransport`, `PullPage`, `OpPushResult`, `FetchSuccess`/`FetchNotFound`/`FetchError`, `SyncStarted`, `FullResyncStarted`, `JsonConverter`. Kütüphane dışından `extends`/`implements` (mock dahil) artık derlenmez. Bilinçli değilse geri alınmalı; yayın öncesi `dart_apitool` ile tam API farkı önerilir.
- **`todo_simple` ve `todo_simple_new` frontend'leri** de `store_date_time_values_as_text` kullanmıyor (saniyeye kırpma); backend'leri taban sürümü kontrolü yapıyor. `todo_advanced`'deki aynı `build.yaml` + göç uygulanmalı.
- **Aralıklı e2e testi:** `offline_first_sync_drift_rest/test/e2e/full_resync_e2e_test.dart › fullResync handles server with many items (pagination)` 2026-09-19'da ~23 tam koşuda 2 kez düştü (`TransportException: HTTP error 500`, ikisinde de büyük çekirdek paketinin hemen ardından, makine yük altındayken); tek başına 5/5, ardışık 14 tam koşuda 0 düşüş, CI'da 2/2 yeşil. Test sunucusu UTC (`Z`) damgası ürettiği için K1-7 değişikliği devrede değil; testin kendi yorumu yük altında geçici 500'leri belgeliyor. **Kök neden bulunamadı.** Öneri: `test/e2e/helpers/test_server.dart`'taki `catch (e, st)` bloğunda istisnayı `stderr`'e yazdır — bir sonraki düşüş kendini açıklar. Not: aynı işleyicide `pageToken` (mutlak indeks) her istekte `updatedSince` ile yeniden filtrelenen listeye uygulanıyor; bu yüzden sayfalamada bir öğe atlanıyor (test bunu `pulled >= 4` ile tolere ediyor) ve `startIndex > items.length` olursa `sublist` `RangeError` → 500 üretir.
- **Gövdesiz başarı yanıtı veren sunucular:** sürüm öğrenilemediği için kuyruktaki sonraki düzenleme conflict olarak çözülür (kayıp yok, fazladan tur var). İstenirse başarıdan sonra `fetch` ile sürüm öğrenilebilir.

---

## Kademe 2 — Sağlamlık ve yaşam döngüsü

### offline_first_sync_drift — çalışma zamanı
| ID | Bulgu | Yer | Durum | Efor |
|---|---|---|---|---|
| K2-1 | `dispose()` sync sürerken çağrılırsa `StateError: Cannot add new events after calling close`. `lib/`'de hiç `isClosed` koruması yok. Düzeltme: tüm yayınları `_emit()` üzerinden geçir. | `sync_engine.dart:663-673` | ✅ okundu | S |
| K2-2 | `startAuto`: `Timer.periodic(interval, (_) => sync())` future'ı düşürüyor → her başarısız tick unhandled async error. `_scheduleEnqueuePush` doğrusunu yapıyor (`unawaited(...catchError)`). | `sync_engine.dart:226` | ✅ okundu | S |
| K2-3 | Devam eden kind koşusuna push/pull kapsamına bakılmadan katılınıyor → push isteyen, pull-only koşunun sonucunu alıyor ve **push sessizce düşüyor**. `test/sync_engine_test.dart:2678-2710` bu davranışı sabitliyor. Düzeltme: anahtar olarak `(String kind, bool push, bool pull)` record'u; tam eşleşme yoksa zincirle. | `sync_engine.dart:324-343` | 📋 ajan | M |
| K2-4 | Push-only `sync()` tam resync kapısını tetikleyebiliyor (kapı `pushKinds`/`pullKinds`'e bakmıyor). `resetAll` pull'dan önce, `setLastFullResync` sonra → yarıda kesilen resync her seferinde sıfırdan başlıyor. | `sync_engine.dart:289-307`, `:561`, `:575` | 📋 ajan | M |
| K2-5 ✔ | `ops.firstWhere` `orElse`'süz: transport bilinmeyen `opId` döndürürse `StateError` → tüm batch'in başarıları ack'lenmiyor. Ayrıca batch başına O(n²) (500×500/2 dizgi karşılaştırması); `successOpIds` `List` + `contains`. Düzeltme: `{opId: op}` map'i, `Set<String>`. | `push_service.dart:101`, `:181` | ✅ okundu | S |
| K2-6 | `firstError` eşzamanlı kind'lar arasında karışıyor: her koşu paylaşılan broadcast `events`'i kind filtresiz dinliyor. | `sync_engine.dart:361-368`, `:539-546` | 📋 ajan | S |
| K2-7 | `SyncCoordinator`: `_started = true` await'ten önce set ediliyor → açılışta çevrimdışıysa `startAuto` ve outbox aboneliği hiç kurulmuyor, `start()` yeniden çağrılsa da no-op. `watchPendingPushCount().distinct()` yüzünden başarısız push yeniden denenmiyor. | `sync_coordinator.dart:60-78` | 📋 ajan | S |
| K2-8 | `_mergeResults` boş listede `results.last` → `Bad state: No element`. `stuckOpsCount` kind filtresiz sorgulanıyor. | `sync_engine.dart:427-476`, `:404`, `:592` | 📋 ajan | S |

### offline_first_sync_drift — veri katmanı
| ID | Bulgu | Yer | Durum | Efor |
|---|---|---|---|---|
| K2-9 | `ORDER BY ts` eşitlik bozucusuz; `ts` ms'e kırpılıyor → aynı ms'deki iki op keyfi sırada. **P1 ile birlikte gönderilmeli** (indeks bu "kazara" sırayı değiştiriyor). Düzeltme: `ORDER BY ts, rowid` (şema değişikliği gerektirmez). | `sync_database.dart:174`, `:363`, `:84` | ✅ okundu · ✔ düzeltildi (0.2.0): `ORDER BY ts, rowid` | S |
| K2-10 | README'nin birincil yazma örüntüsü atomik değil ("önce yerel tabloyu güncelle, sonra `db.enqueue`"); iki await arasında çökme → satır yazılmış, op yok, hiçbir şey fark etmiyor. `SyncEntityWriter.writeAndEnqueueOp` doğru (tek transaction). Düzeltme: README sırasını değiştir, `enqueue`'ya dartdoc uyarısı. | `README.md:300-340`, `sync_database.dart:83` | 📋 ajan | S |
| K2-11 | `_rowsToOps`: tanınmayan `op` değeri boş payload'lı `UpsertOp`'a düşüyor → sunucu kaydını boşaltabilecek PUT. Düzeltme: wire değerli enhanced enum + `tryParse`; eski `static const` dizgiler deprecated alias kalır. | `sync_database.dart:385-398` | 📋 ajan | M |
| K2-12 | Zaman damgası hassasiyeti: outbox `ts`/`baseUpdatedAt`'ı ms olarak saklıyor (µs kaybı). Doğruluk ayrıca drift'in `store_date_time_values_as_text: true` seçeneğine bağlı; README bunu kritik olarak işaretlemiyor (onsuz drift **saniye** saklar). | `sync_database.dart:84,87,106`, `README.md:154` | 📋 ajan · kısmen (0.2.0): outbox tabanı artık µs; README notu eklendi. `ts` kolonu hâlâ ms | M |
| K2-13 | `purgeOutboxOlderThan` `sync_outbox_meta` satırlarını yetim bırakıyor; `ackOutbox`'ın iki statement'ı aynı transaction'da değil. | `sync_database.dart:473-480`, `:431-437` | 📋 ajan | S |
| K2-14 | `clearSyncableTables`: N ayrı transaction'sız `DELETE`; yarıda kalırsa bazı tablolar silinmiş olur. Cursor sıfırlamayla aynı transaction'a alınmalı. | `sync_database.dart:495-499` | 📋 ajan | S |

### offline_first_sync_drift_rest
| ID | Bulgu | Yer | Durum | Efor |
|---|---|---|---|---|
| K2-15 | Batch modu hata fırlatıyor (tek-op modu `PushError`'a çeviriyor) → `ack`/`recordFailures` çalışmıyor, `tryCount` 0'da kalıyor: kalıcı 400 veren tek chunk kuyruğu sonsuza dek tıkıyor. Sıralı döngüde 3. chunk fırlatırsa 1–2'nin sonuçları atılıyor. İki test bu davranışı sabitliyor. | `rest_transport.dart:232-305` | 📋 ajan | S |
| K2-16 | 401 işlenmiyor; token `push()` başına bir kez alınıyor (500 op'a kadar). Süresi dolan token → her op `PushError` → 5 sync sonra hepsi "stuck". Düzeltme: `_withRetry` içinde tek seferlik yenile-ve-dene. | `rest_transport.dart:160`, `:449-451` | 📋 ajan | M |
| K2-17 | `If-Match` ölü kod (hiçbir çağıran `version:` geçmiyor); 412/428 conflict sayılmıyor. Üç ayrı durum merdiveni (`_parseResponse`, `_pushDelete`, `_parseBatchItem`) birbirinden sapmış → tek `switch` sınıflandırıcı. | `rest_transport.dart:91-101`, `:425`, `:411`, `:307` | 📋 ajan | S/M |
| K2-18 | `RestTransport` kendi oluşturduğu `http.Client`'ı hiç kapatmıyor; `TransportAdapter` sözleşmesinde `close()` yok. Dikkat: `abstract interface class`'a metot eklemek dış implementer'ları kırar → opsiyonel `Closeable` kontrolü. | `rest_transport.dart:52`, `transport_adapter.dart:49-73` | 📋 ajan | S |
| K2-19 | Batch: eksik `statusCode` 200 sayılıyor → op başarıyla ack'lenip **sessizce kayboluyor** (doküman alanı zorunlu sayıyor; varsayılan bir testle sabit). Bozuk öğe `TypeError`'ı `NetworkException` olarak etiketleniyor. | `rest_transport.dart:309`, `:302-307` | 📋 ajan | S |
| K2-20 | Örnek backend DELETE için `X-Base-Updated-At` header'ını okuyor; transport (ve doküman, ve e2e test sunucusu) `?_baseUpdatedAt` kullanıyor → örnekte silme conflict tespiti **kapalı**. Transport doğru, örnek yanlış. | `example/todo_advanced/backend/routes/todos/[id].dart:129` | 📋 ajan | S |
| K2-21 | `pull`'daki tembel `.cast<>()` bozuk öğede `TypeError`'ı transport sınırında değil `PullService`'in drift batch'inde fırlatıyor. | `rest_transport.dart:140-141` | 📋 ajan (çalıştırılmadı) | S |

### sync_socket_wake_listener
| ID | Bulgu | Yer | Durum | Efor |
|---|---|---|---|---|
| K2-22 | Ateşle-unut `engine.sync()` → tam da ağın güvenilmez olduğu anda unhandled async error. `_catchUpSync` doğrusunu yapıyor. | `network_sync_handler.dart:61-66`, `app_lifecycle_sync_handler.dart:55` | 📋 ajan | S |
| K2-23 | `_setupSocket()` tek-uçuş korumasız; üç çağrı noktası iki `await` boşluğunda yarışıyor → izlenmeyen canlı soket (kendi `sync:wake` handler'ı ve sonsuz reconnect'li Manager'ıyla) sızıyor. Ajan replika ile yeniden üretti. Düzeltme: `_setupInFlight ??= ...` + `_disposed` koruması. | `socket_wake_listener.dart:155-189`, `:240-247` | 📋 ajan | S |
| K2-24 | `start()` idempotent değil: `WidgetsBinding._observers` bir `List`, `removeObserver` yalnızca ilkini siler → çift `start()` sonrası `dispose()` eksik kalır; handler → engine → DB süreç boyunca tutulur. `NetworkSyncHandler.start()` aboneliğin üzerine yazıyor. | `app_lifecycle_sync_handler.dart:38,41`, `network_sync_handler.dart:37-45` | 📋 ajan | S |
| K2-25 | `inactive`/`hidden` arka plan sayılıyor → iOS'ta her Control Center bakışı: soket yıkımı + handshake + `authProvider()` + tüm kind'lar için sync (×2, `AppLifecycleSyncHandler` ile). `startAuto` her resume'da sıfırlandığı için 30 dk'lık "güvenlik ağı" timer'ı sık açılan uygulamada hiç ateşlenmiyor. | `socket_wake_listener.dart:137-148`, `app_lifecycle_sync_handler.dart:48-73` | 📋 ajan | M |
| K2-26 | Her socket.io yeniden bağlanmasında `_catchUpSync` (debounce yok); 60 sn'lik reconnect timer'ı arka planda iptal edilmiyor. | `socket_wake_listener.dart:160-163`, `:191-195` | 📋 ajan | S |
| K2-27 | Sync sürerken gelen `sync:wake` kayboluyor: çağıran devam eden koşuya katılıyor, o koşunun pull'u ise wake'i doğuran yazmadan önce başlamış olabilir; sonrasında yeniden çalıştırma yok. Düzeltme: bekleyen wake kümesi + koşu bitince yeniden ateşle. | `socket_wake_listener.dart:201-215` (kök: `sync_engine.dart:324-342`) | 📋 ajan (orta-yüksek güven) | M |
| K2-28 | `NetworkSyncHandler._wasOffline` başlangıç durumundan tohumlanmıyor → çevrimdışı başlayıp çevrimiçi olan ilk geçiş kaçabiliyor (akışın ilk yayını abone sırasına bağlı). Düzeltme: `checkConnectivity()` ile tohumla. | `network_sync_handler.dart:30,37-39,51-57` | 📋 ajan (orta güven) | S |
| K2-29 | Fırlatan `authProvider` → CONNECT paketi hiç gönderilmiyor, soket yarı açık kalıyor, 60 sn'de bir sessizce yeniden deneniyor. | `socket_wake_listener.dart:184-187` | 📋 ajan | S |
| — | Paketleme: `README.md` / `CHANGELOG.md` / `LICENSE` yok (pub.dev puanı); `onWake` dokümanı var olmayan bir varsayılandan bahsediyor. | paket kökü, `socket_wake_listener.dart:87-89` | 📋 ajan | S |

### search_engine
| ID | Bulgu | Yer | Durum | Efor |
|---|---|---|---|---|
| K2-30 | Trigram'da 1–2 karakterlik sorgular hep boş (token'lar tam 3 karakter). Yazarken-arama ilk iki tuşta boş liste gösterir. Düzeltme: `< 3` karakterde `null` ("yazmaya devam") ya da normalize kolonlarda `LIKE` yedeği; sınırı belgele. | `tables/search_tables.drift:33`, `search_database.dart:404-477` | ✅ çalıştırıldı (`f`,`fo`→0; `fox`→1) | S |
| K2-31 | Tek zehirli satır bir kind'ı sonsuza dek donduruyor: cursor yalnızca sayfa bitince yazılıyor, 3. satırda fırlatma → sonraki tetiklemede yine 3'te ölüyor. İndeksleyicinin `catch`'i tamamen sessiz. Kuyruk yolundaki `_maxPendingTries` korumasının cursor yolunda karşılığı yok. | `search_indexer.dart:107-148` | 📋 ajan | M |
| K2-32 | `addSearchItems(processNow: true)` `_lock`'u atlıyor (`processPendingItems` ve `indexNow` alıyor). | `search_engine.dart:102-111` | 📋 ajan | S |
| K2-33 | `INSERT OR REPLACE` satırı silip yeniden eklediği için `try_count` 0'a dönüyor → her sync'te yeniden kuyruğa giren satır dead-letter sınırına hiç ulaşmıyor. | `search_database.dart:134-151` | 📋 ajan | S |
| K2-34 | Saat kayması koruması yok: gelecek tarihli (ör. 2030) tek satır `lastIndexedAtMs`'i ileri taşır, sonrası hiç indekslenmez. | `search_indexer.dart:128-137` | 📋 ajan (orta güven) | S |
| K2-35 | `tableUpdates`, `kind`'ın drift tablo adına eşit olduğunu varsayıyor; değilse akış hiç ateşlenmiyor, hata da yok. e2e testi tabloyu `'rows'` adlandırarak bunu atlıyor. | `search_indexer.dart:66-71` | 📋 ajan | S |
| K2-36 | Belgelenen "sondaki boşluk = tam ifade" seçeneği ve `*` soneki trigram altında etkisiz. | `search_database.dart:414-423` | 📋 ajan | S |

### drift_helpers
| ID | Bulgu | Yer | Durum | Efor |
|---|---|---|---|---|
| K2-37 | `JsonConverter.toSql(null)` → `'{}'`: kolon hiç SQL NULL olamıyor, `null` → `{}` olarak geri okunup sunucuya öyle push ediliyor. Kardeş `JsonListConverter` doğru (`null` döndürüyor). İki test mevcut davranışı sabitliyor → **sahip kararı**; mevcut DB'ler için `UPDATE ... SET col = NULL WHERE col = '{}'` gerekir. | `converters/json_converter.dart:26-30` | ✅ okundu | S + göç |
| K2-38 | `fromSql` her şeyi yutuyor, `fromJson` korumasız: `fromJson([1, null, 3])` `TypeError` fırlatıyor, `fromSql('[1,null,3]')` `[]` döndürüyor (tek bozuk öğe tüm listeyi düşürüyor). | `list_int_converter.dart:15-35`, `list_string_converter.dart:41-46` | 📋 ajan | S |
| K2-39 | `catch` blokları `FormatException` mesajını (kaynak metnin ~78 karakteri: token/PII) ve stack trace'i `dart:developer.log` ile yazıyor; `log` release'te ayıklanmaz. Bozuk kolonda satır başına maliyet. | dört converter'ın `catch`'leri | 📋 ajan | S |
| K2-40 | Aynı converter duruma göre `const []` ya da büyüyebilir liste döndürüyor → veriye bağlı `UnsupportedError`. | `list_string_converter.dart:23-34`, `list_int_converter.dart:15-25` | 📋 ajan | S |
| K2-41 ✔ | Transport bir op için sonuç döndürmezse (`BatchPushResult.results` eksik) op ne ack'leniyor ne hata sayılıyor; `while (true)` aynı op'u yeniden alıp yeniden push ediyor → `sync()` dönmüyor, sunucu sürekli vuruluyor (K1-1'in transport kaynaklı ikizi). Düzeltme: yanıtsız op `TransportException` ile başarısız sayılıyor (`tryCount`+1, `OperationFailedEvent`) ve push bitiyor. Bilinmeyen `opId` için sonuç hâlâ fırlatıyor, artık op id'sini söyleyerek. | `push_service.dart` (`pushAll`) | ✅ çalıştırıldı (kırmızı→yeşil: `push_bookkeeping_test.dart`) | S |
| K2-42 ✔ | REST push/delete/batch-öğesi hataları `http.ClientException('Push failed 401')` olarak dönüyordu: durum kodu yalnızca metnin içinde, `SyncErrorInfo.category` hep `unknown` → motor süresi dolmuş token'ı ya da kesintiyi reddedilmiş op'tan ayıramıyordu. Düzeltme: `TransportException.httpError(status, body)` (`FetchError` zaten böyleydi). İki birim testi eski tipi sabitliyordu, güncellendi. | `rest_transport.dart` (`_parseResponse`, `_pushDelete`, `_parseBatchItem`) | ✅ çalıştırıldı · 0.2.2 | S |
| K2-43 ✔ | `todo_advanced` backend'i `includeDeleted`'ı yok sayıp silinenleri hiç döndürmüyordu → bir cihazdaki silme diğer cihazlara **hiç** ulaşmıyordu (diğer iki örnek backend doğru). Ayrıca `backend-transport.md` "tombstone gelen kayıt yerelden silinir" diyordu; kod ise satırı `deleted_at` ile **saklıyor** (tasarım: `SyncColumns.deletedAt/deletedAtLocal`, uygulama filtreler). Hard delete paragrafı da yanlıştı (varsayılan `clearData: false` ile full resync silmeyi yakınsamıyor). Backend + dokümanlar düzeltildi. **Açık (sahip kararı):** yerel tombstone temizliği için yardımcı API ve hard delete'i yakınsayan resync modu yok. | `example/todo_advanced/backend/lib/repositories/todo_repository.dart`, `routes/todos/index.dart`, `docs/backend-transport.md` | ✅ çalıştırıldı | S |
| K2-44 ✔ | `sync_cursors.ts` ms saklıyordu (outbox'ta düzeltilen hatanın ikizi): µs sürümlü sunucuda cursor son satırın hemen **öncesine** düşüyor, o ms içindeki satırlar her pull'da yeniden iniyordu (kayıp yok, sonsuz israf). Düzeltme: outbox'la ortak µs kodlayıcı; şema değişmedi, eski ms cursor'lar büyüklükten tanınıyor. | `sync_database.dart` (`setCursor`/`getCursor`), `internal/timestamp_codec.dart` | ✅ çalıştırıldı · 0.2.2 | S |
| K2-45 ✔ | 0.2.0'daki µs kodlamasında köşe durum: 1966–1973 arası bir damganın µs değeri `1e14` eşiğinin altında kaldığı için geri okunurken ms sanılıyordu (`1970-01-01T00:00:05Z` → `01:23:20Z`). `updated_at`'i epoch'a varsayılanlanmış eski satırlarda taban sürümü / cursor bozulurdu. Düzeltme: eşiğin altındaki değerler ms olarak **yazılıyor** → kodlama her tarih için tam tersinir. | `internal/timestamp_codec.dart` | ✅ çalıştırıldı · 0.2.2 | S |
| K2-46 ✔ | Ağ yokken `RestTransport.push` batch'teki **her** op'u ayrı ayrı deniyordu; her biri kendi retry + backoff'unu (varsayılanlarla ≥31 sn, kara delik ağda ~3,5 dk) tüketiyordu → 100 op'luk kuyrukta tek bir çevrimdışı `sync()` ~1 saat sürebilir. Düzeltme: bir op ağ hatasıyla (retry'lardan sonra) ya da `401` ile düşünce kalan op'lar gönderilmeden aynı hatayı alıyor. `403`/`4xx`/`5xx` batch'i durdurmuyor (tek op'la ilgili olabilir). Ayrıca kodlanamayan payload retry döngüsünden çıkarılıp op'a özgü hata yapıldı (aksi hâlde yeni kuralla kuyruğu tıkardı). | `rest_transport.dart` (`push`, `_pushUpsert`) | ✅ çalıştırıldı · 0.2.2 | S |

---

## Kademe 3 — Performans ve bellek

| ID | Fırsat | Yer | Beklenen kazanç | Durum | Efor | Kırıcı mı |
|---|---|---|---|---|---|---|
| P1 ✔ | `sync_outbox`'ta hiç indeks yok. `takeOutbox`: `SCAN` + `USE TEMP B-TREE FOR ORDER BY`, `SELECT *` ile payload'lar dahil tüm satırlar okunup sıralanıyor; `pushAll` bunu batch başına yeniliyor. `watchOutboxCount` her insert/ack/tryCount güncellemesinde tam `COUNT(*)`. Öneri: `(ts)`, `(kind, ts)`, `(tryCount)`. **K2-9 ile birlikte.** | `tables/outbox.dart:35-39`, `sync_database.dart:171-177`, `:209-213` | N op boşaltma O(N²/pageSize) → O(N) | ✅ okundu | M | Şema. Kırmayan yol: init'te idempotent `CREATE INDEX IF NOT EXISTS` |
| P2 ✔ (kalan: native'de ms hassasiyetli tabanlarda op başına PK okuması, ~5 ms / 100 op) | N+1: `_reStampBaseUpdatedAt` op başına sıralı `SELECT * ... LIMIT 1` (batch başına 500'e kadar), ağ çağrısından önce. Öneri: kind başına tek `WHERE pk IN (...)` (≤ ~900 değişkenlik parçalar); yalnızca değer değiştiyse kopya ayır. | `push_service.dart:227-295` | Mobilde batch başına ~100–500 ms | 📋 ajan · büyük ölçüde giderildi (0.2.0): satır okuması yalnızca ms hassasiyetli tabanlarda | M | hayır |
| P3 ✔ | `_applyServerRow` her başarıda ayrı statement + örtük transaction; `ack` ile atomik değil. Öneri: döngüde topla, `ack`'ten önce tek `batch`. | `push_service.dart:111-113`, `:307-318` | 500 commit → 1 | ✅ okundu | S | hayır |
| P4 | search: cursor indekslemesi satır başına bir kilit + bir transaction. Öneri: `upsertAll` (varsayılan gövdeli) + sayfa başına tek transaction; `_deleteNoTxn`'de `DELETE ... RETURNING`. | `search_engine.dart:79-83`, `search_database.dart:302-336`, `search_indexer.dart:107-126` | Masaüstü SSD'de ölçülen 4,7× (2000 satır: 0,232 sn → 0,049 sn); mobil flash'ta daha fazla | 📋 ajan | M | hayır |
| P5 | FTS indeksi ham + normalize metni iki kez tutuyor. Aynı 8,9 MB külliyatta: mevcut 57,9 MB; ham kolonlar `UNINDEXED` → 38,4 MB (−%34); `unicode61` → 26,0 MB (−%55, ama kelime-içi eşleşme kaybolur ve Türkçe `ı`/`ç` yine katlanmaz). **Bedel:** `highlight()`/`snippet()` `UNINDEXED` kolonda işaretsiz döner → vurgu normalize kolonlara taşınıp ofsetler istemcide ham metne uygulanmalı (normalizer karakter-başına eşleme olduğu sürece kesin). | `tables/search_tables.drift:23-34`, `search_database.dart:437-440` | Cihazdaki DB boyutu −%34 | 📋 ajan | L | Şema + göç |
| P6 | `SELECT *`: her sonuç tam `content` **ve** `content_normalized` taşıyor; UI ~66 karakterlik snippet gösteriyor. Öneri: kolonları adlandır, `includeContent` bayrağı, `*_normalized` okumalarını `fromSql`'den çıkar. | `search_database.dart:464-468`, `models/global_search.dart:44-58` | 50 KB'lık belgelerde 50 sonuç ≈ tuş başına 5 MB string | 📋 ajan | S | bayrakla hayır |
| P7 | `processPendingItems` yazmadan önce 5000 payload'ı çözüp iki liste hâlinde bellekte tutuyor. Öneri: iç sayfalama; tek satırlık hafifletme: varsayılan `batchSize` ~500. | `search_engine.dart:116-130`, `search_database.dart:160-187` | 20 KB/satırda tepe ~200 MB | 📋 ajan | S–M | hayır |
| P8 | REST pull: bayt → String → ağaç. `const Utf8Decoder().fuse(const JsonDecoder())` doğrudan bayttan ayrıştırıyor. Ayrıca `Response.body` her erişimde yeniden çözen bir getter (`_parseResponse:430,432` iki kez çağırıyor). | `rest_transport.dart:136` | 191 KiB / 500 satırlık sayfada ölçülen 1,6× (497 µs → 310 µs) + ara String yok | 📋 ajan | S | hayır |
| P9 | `Future.wait` chunk'ı bariyer: her chunk `max(gecikme)` kadar sürüyor. `_nextBackoff` saf `d * 2` (jitter yok) → eşzamanlı retry dalgaları. | `rest_transport.dart:168-183`, `:601-604` | Kuyruk gecikmesi; sunucu üzerindeki dalgalar | 📋 ajan | S–M | hayır |
| P10 ✔ | `recordOutboxFailures`: başarısız op başına bir round-trip; `catch` tüm döngüyü sardığı için 3. girdide hata 4..N'yi sessizce düşürüyor. Öneri: `batch.insertAllOnConflictUpdate`. | `sync_database.dart:281-293` | 500 statement → 1 | 📋 ajan | S | hayır |
| P11 ✔ | `SyncEntityWriter._payload`: `.cast<String, Object?>()` gereksiz `CastMap` sarmalayıcısı üretiyor (düz upcast `identical`); `replaceAndEnqueueDiff` kullanıcı kodu olan `toJson`'u güncelleme başına iki kez çağırıyor. `ChangedFieldsTracker.fields` her çağrıda kopya ayırıyor. | `sync_writer.dart:68-69`, `:150-162`, `changed_fields.dart:26` | Yazma başına ayırmalar | 📋 ajan | S | hayır |

---

## Dil düzeyi fırsatlar (extension types vb.)

Beş ajanın bağımsız ortak sonucu: **bu kod tabanında kayda değer extension type adayı yok.**

- `opId` / `kind` / `entityId` zaten çıplak `String`. Extension type çalışma zamanında silindiği için ortadan kalkacak bir sarmalayıcı nesne yok → bellek kazancı sıfır; buna karşılık yayınlanmış paketin public tipleri değişir ve her `Variable.withString`/`jsonEncode` noktasında açma gerekir.
- `Cursor`, `MergeInfo`, `PreservingMergeResult`, `SearchIndexCursor`: öğe başına değil sayfa/conflict/batch başına ayrılıyor (~32–100 bayt) → API kırılmasına değmez.
- Extension type'lar `is` ile sınanamaz ve `==`/`hashCode` override edemez; `sealed PushResult` eşlemesi buna dayanıyor.
- Converter'lar için de hayır: maliyet sarmalayıcı değil, ayrılan `Map`. Hiç okunmayan kolonların hevesli çözülmesi profilde öne çıkarsa doğru çözüm silme değil, ezberleyen tembel bir `TypeConverter`.

Gerçekten değer katanlar: K2-3'teki private `(kind, push, pull)` record anahtarı; K2-11'deki enhanced enum; K2-17'deki tek `switch` sınıflandırıcı.

## İncelenip sorun bulunmayanlar (kapsam kaydı)

`_ensureFullResync` tek-uçuşu · `_kindRunFutures` temizliği · `_pushBatch` backoff/kırpma · enqueue-push timer yaşam döngüsü · pull yazma→cursor sırası (çökme-güvenli) · `writeAndEnqueueOp` atomikliği · `OpId.v4` (122 bit entropi) · `ChangedFieldsDiff._deepEquals` (NaN dahil) · REST batch sonuç sıralaması ve eksik op sentezi · idempotency anahtarları · `maxRetries` sayımı · sorgu parametresi kodlaması · sondaki `/` normalizasyonu · `Retry-After` kırpması · FTS5 `MATCH` enjeksiyonu (`quote()` doğru; `NEAR`, `*`, `-`, `(`, `:` tırnak içinde literal; 3000 karakterlik sorgu hata vermiyor) · `highlight`/`snippet` kolon ofsetleri · `upsertSearchItem` rowid tutarlılığı · `watchSearchGlobal` geçersiz kılma · elle yazılmış `PendingSearchItem ==`/`hashCode` · `payload_helpers.dart` · güvenilmeyen `kind`'ın `sync`'e ulaşması (bilinmeyen kind no-op) · `sync:wake` payload ayrıştırması · `connectivity_plus` `none` anlamı.

## Sahibine sorular (öncelikleri değiştirir)

1. Arama `transport.search` üzerinden mi, doğrudan `searchGlobal(normalizer:)` ile mi çağrılıyor? (K1-9)
2. Production'da `pushConcurrency > 1` var mı? (K1-5)
3. Sunucular zaman damgalarını `Z` ekli mi gönderiyor? (K1-7) `_baseUpdatedAt` tam eşleşmeyle mi, toleransla mı karşılaştırılıyor? (K2-12)
4. Trigram bilinçli bir seçim mi (kelime-içi eşleşme ürün gereksinimi mi)? (P5, K2-30)
5. Push-only `sync()`'in tam resync tetiklemesi kasıtlı mı? (K2-4)
6. Çözülemeyen conflict `tryCount`'a sayılsın mı? (K1-1)
7. `JsonConverter.toSql(null) == '{}'` davranışına bağımlı bir tüketici uygulama var mı? (K2-37)
8. Gerçek backend'ler 409 yerine 412 döndürüyor mu? (K2-17) Devamı olan boş sayfa döndürüyor mu? (K1-7c)

## Önerilen sıra

1. **PR 1 — Kademe 1, kırıcı olmayanlar:** K1-1, K1-2, K1-3, K1-4, K1-6, K1-7 (+ istenirse K1-8, K1-9). Her biri için önce kırmızı, sonra yeşil regresyon testi.
2. **PR 2 — çekirdek performans:** P1 + K2-9 (birlikte), P2, P3, K2-5, P10.
3. **PR 3 — search:** P4, P6, P7, K2-30..K2-33.
4. **PR 4 — yaşam döngüsü:** K2-1, K2-2, K2-22..K2-24, K2-26, K2-29.
5. Tasarım/ürün kararı gerektirenler en sona: K1-5 (worker havuzu), K2-3, K2-4, K2-25, K2-27, P5, K2-37.
