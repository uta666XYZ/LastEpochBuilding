# LETools Extraction Scripts

再利用可能なLETools抽出用JavaScriptスクリプト集。DevToolsコンソールで実行する。

対象サイト: `https://www.lastepochtools.com/db/`

---

## 1. i18n翻訳データロード

ほぼ全ての抽出で必要。他スクリプト実行前に一度だけ実行すれば `window._i18n` にキャッシュされる。

```javascript
await fetch('https://www.lastepochtools.com/data/version142/i18n/full/en.json?14')
  .then(r=>r.json()).then(j=>{window._i18n=j;});
```

> バージョン部分 `version142` は LE バージョンに応じて更新要。

---

## 2. 全affix完全リファレンス抽出

1112件全affixの `type / sat / cs / canRollOn / name / title` を含むリファレンス生成。
P/S判定・sat分類の基準になる最重要ファイル。

**出力:** `letools_affix_type_reference.json`

```javascript
(function(){
  const t = k => (window._i18n && window._i18n[k]) || k;
  const all = [...Object.values(window.itemDB.affixList.singleAffixes),
               ...Object.values(window.itemDB.affixList.multiAffixes)];
  const out = {};
  for (const a of all) {
    out[a.affixId] = {
      type: a.type === 0 ? 'Prefix' : 'Suffix',
      cs: a.classSpecificity,
      canRollOn: a.canRollOn,
      sat: a.specialAffixType,
      name: t(a.affixDisplayNameKey),
      title: t(a.affixTitleKey)
    };
  }
  console.log('total:', Object.keys(out).length);
  const blob = new Blob([JSON.stringify(out,null,2)],{type:'application/json'});
  const a = document.createElement('a'); a.href=URL.createObjectURL(blob);
  a.download='letools_affix_type_reference.json'; a.click();
})();
```

---

## 3. sat（specialAffixType）別抽出

sat値で絞り込んで抽出する汎用テンプレ。

sat値対応表:
- 0: normal (766)
- 1: experimental (12)
- 2: unique_named — Personal(12)+Champion(14) (26)
- 3: reforged / set (59)
- 4: sealed_suffix dual-stat idol-only (49)
- 5: sealed_prefix dual-stat idol-only (66)
- 6: corrupted (134)

```javascript
(function(){
  const SAT = 2;  // ← ここを変更
  const t = k => (window._i18n && window._i18n[k]) || k;
  const all = [...Object.values(window.itemDB.affixList.singleAffixes),
               ...Object.values(window.itemDB.affixList.multiAffixes)];
  const out = all.filter(a => a.specialAffixType === SAT).map(a => ({
    affixId: a.affixId,
    type: a.type === 0 ? 'Prefix' : 'Suffix',
    name: t(a.affixDisplayNameKey),
    title: t(a.affixTitleKey),
    canRollOn: a.canRollOn,
    cs: a.classSpecificity,
    rarityTier: a.rarityTier,
    group: a.group,
    weighting: a.weighting,
    levelRequirement: a.levelRequirement
  }));
  console.log(`sat=${SAT} count:`, out.length);
  const blob = new Blob([JSON.stringify(out,null,2)],{type:'application/json'});
  const a = document.createElement('a'); a.href=URL.createObjectURL(blob);
  a.download=`sat${SAT}_affixes.json`; a.click();
})();
```

---

## 4. カテゴリページ抽出（`.item-card` 形式）

**対象ページ例:**
- `/db/category/helms/prefixes` (helmet prefix全215件など)
- `/db/personal-affixes`

DOMに `.item-card.item-affix` カードが並ぶタイプ。サブクラスで絞り込み可能（例: `.personal`）。

```javascript
(function(){
  const SUBCLASS = '';  // '.personal', '.champion' などで絞り込み可。空文字で全件
  const sel = `.item-card.item-affix${SUBCLASS}`;
  const items = [...document.querySelectorAll(sel)].map(el => ({
    encodedId: el.querySelector('[prefix-id]')?.getAttribute('prefix-id')
            || el.querySelector('[suffix-id]')?.getAttribute('suffix-id'),
    type: el.querySelector('[prefix-id]') ? 'Prefix' : 'Suffix',
    name: el.querySelector('.item-name')?.textContent?.trim(),
    title: el.querySelector('.affix-title')?.textContent?.trim()
  }));
  console.log('count:', items.length);
  const blob = new Blob([JSON.stringify(items,null,2)],{type:'application/json'});
  const a = document.createElement('a'); a.href=URL.createObjectURL(blob);
  a.download='affix_list.json'; a.click();
})();
```

---

## 5. テーブル形式ページ抽出（`[prefix-id]`/`[suffix-id]` 直接）

**対象ページ例:**
- `/db/champion-affixes`

`.item-card` が無くテーブル行に `[prefix-id]` / `[suffix-id]` 属性が付いているタイプ。

```javascript
(function(){
  const items = [...document.querySelectorAll('[prefix-id], [suffix-id]')].map(el => ({
    encodedId: el.getAttribute('prefix-id') || el.getAttribute('suffix-id'),
    type: el.hasAttribute('prefix-id') ? 'Prefix' : 'Suffix',
    name: el.textContent.trim(),
    href: el.getAttribute('href')
  }));
  console.log('count:', items.length);
  const blob = new Blob([JSON.stringify(items,null,2)],{type:'application/json'});
  const a = document.createElement('a'); a.href=URL.createObjectURL(blob);
  a.download='affix_list.json'; a.click();
})();
```

---

## 6. ページ構造診断（未知ページ用）

新しいページの構造が分からないとき最初に実行する。

```javascript
(function(){
  console.log('URL:', location.href);
  const selectors = [
    '.item-card','.item-card.item-affix','.affix-card',
    '[data-affix-id]','[prefix-id]','[suffix-id]',
    '.affix','.affix-entry','.affix-row',
    'table tr','a[href*="/prefixes/"]','a[href*="/suffixes/"]',
    '.list-item','.db-entry','.entry'
  ];
  for (const s of selectors) {
    const n = document.querySelectorAll(s).length;
    if (n) console.log(`${s}: ${n}`);
  }
  // affixカードに付いている全classを列挙
  const classes = new Set();
  document.querySelectorAll('.item-card.item-affix').forEach(el => {
    el.classList.forEach(c => classes.add(c));
  });
  if (classes.size) console.log('affix card classes:', [...classes]);
  // 最初の要素サンプル
  const first = document.querySelector('.item-affix, [prefix-id], [suffix-id]');
  if (first) console.log('sample HTML:', first.outerHTML.slice(0,500));
})();
```

---

## 7. アイテム（Unique/Set）抽出テンプレ

過去セッションで使用した全ユニーク/セット抽出のテンプレ。`window.itemDB.uniqueItems` 等のリストから全情報を抽出する。
詳細は `letools_uniques_extracted.json` / `letools_sets_extracted.json` 生成時のスクリプトを参照（別ノート）。

---

## 8. Idol Affix抽出（既存）

`Tools/Idol Affix Extractor in LETools.md` に保管済み。IDOL_IDS=25〜33のaffixを抽出する。

---

## よくあるトラブル

| 症状 | 原因 | 対処 |
|------|------|------|
| ファイルが空 (`count: 0`) | セレクタが合わない | §6で構造診断 |
| nameがi18nキーのまま | `_i18n` 未ロード | §1を先に実行 |
| URL遷移後に動かない | SPAで状態再構築中 | 数秒待つか `window.itemDB` が存在するか確認 |
| encodedIdとnumeric affixIdが紐づかない | DOMとitemDBで表現違い | titleテキストで突合（§Personal/Championマッチ方式） |

---

## 既知のページURL一覧

| URL | 用途 |
|-----|------|
| `/db/items/unique` | ユニーク一覧 |
| `/db/personal-affixes` | Personal affix 12件 |
| `/db/champion-affixes` | Champion affix 14件 |
| `/db/category/helms/prefixes` | Helmet全prefix |
| `/db/category/helms/suffixes` | Helmet全suffix |
| `/db/category/{slot}/{prefixes,suffixes}` | 各スロット別 |

---

## 更新履歴

- 2026-04-20: 初版作成。Personal/Champion抽出、sat別テンプレ、カテゴリページ抽出を統合。
