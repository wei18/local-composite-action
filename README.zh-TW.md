<!-- 同步提醒：修改此檔案時必須同步更新 README.md（見 CLAUDE.md） -->
# 📦 local-composite-action

[English](README.md) | **繁體中文**

[![Test](https://github.com/wei18/local-composite-action/actions/workflows/test.yml/badge.svg)](https://github.com/wei18/local-composite-action/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/wei18/local-composite-action)](https://github.com/wei18/local-composite-action/releases/latest)
[![Marketplace](https://img.shields.io/badge/Marketplace-Setup%20Symlink%20for%20Action%20Repository-blue?logo=github)](https://github.com/marketplace/actions/setup-symlink-for-action-repository)
[![License](https://img.shields.io/github/license/wei18/local-composite-action)](LICENSE)

<img src=".github/social-preview.png" alt="用 uses: ./../org/repo 引用同 repo 的 action — 純 bash、不碰 token、不需 permissions、不需額外 checkout" width="100%">

用 `uses: ./../org/repo/...` 引用自己 repo 裡的其他 action —
即使你的 composite action 是被其他 repo 遠端使用也沒問題。
純 bash、不需額外 checkout、不碰 token、不需要任何 permissions。

## 😖 問題

你的 repo 裡有一個 composite action，想呼叫同 repo 的另一個 local action：

```yaml
# org/repo/.github/actions/main/action.yml
runs:
  using: 'composite'
  steps:
    - uses: ./.github/actions/helper   # ❌
```

在自己 repo 的 workflow 裡這樣寫沒問題，但只要有人遠端使用你的 action
（`uses: org/repo/.github/actions/main@v1`），就會出現令人困惑的錯誤：

```
Error: Can't find 'action.yml' under '...'. Did you forget to run actions/checkout?
```

原因是 `uses: ./...` 是相對於**使用者的** `$GITHUB_WORKSPACE` 解析，
而不是你的 action 在 `_actions/` 底下的 checkout。

## ✨ 解法

在你的 composite action 開頭加一個 step，之後就能用 `./../org/repo/...` 引用同 repo 的 local action：

```yaml
# org/repo/.github/actions/main/action.yml
runs:
  using: 'composite'
  steps:
    - uses: wei18/local-composite-action@v1
      with:
        action_repository: ${{ github.action_repository }}
        action_path: ${{ github.action_path }}

    - name: 執行同 repo 的 local action
      uses: ./../org/repo/.github/actions/helper   # ✅

    - name: 再執行另一個
      uses: ./../org/repo/.github/actions/another-helper   # ✅
```

> [!IMPORTANT]
> `./../org/repo/...` 的路徑請**全部使用小寫** — 不論呼叫端的 `uses:` 大小寫怎麼寫，
> 小寫的 symlink 一定會被建立。

## 🔍 運作原理

Runner 會把你的 action checkout 到 `_actions/` 底下，而 `uses: ./<path>` 是相對於
`$GITHUB_WORKSPACE` 解析。這個 action 用一個 symlink 把兩者接起來：

```
/home/runner/work
├── _actions/org/repo/v1/   ◄─┐  你的 action 的 checkout
├── org/repo ─────────────────┘  本 action 建立的 symlink
└── consumer/consumer/          $GITHUB_WORKSPACE
```

`uses: ./../org/repo/<path>` 就會透過 symlink 解析到你的 checkout —
正是使用者所釘選的那個 commit，路徑也跟你 repo 的目錄結構一致。

- ✅ 不需要 `permissions:`
- ✅ 不碰 token 或 secrets
- ✅ 不連網路 — 純 bash、零依賴

### 為什麼不直接再 `actions/checkout` 一次？

| | local-composite-action | 再跑一次 `actions/checkout` |
|---|---|---|
| 額外 clone | 無 — 重用既有的 checkout | 每個 job 都要完整抓一次 |
| Private repo | 直接可用 | 需要 token/PAT |
| 版本漂移 | 永遠是使用者釘選的 ref | ref 要重複寫一份並保持同步 |
| Workspace | 不動 | 有覆蓋使用者檔案的風險 |

### 即將推出的 `$/` 語法呢？

GitHub 已[提案原生的 `$/` 語法](https://github.com/orgs/community/discussions/26245)
（例如 `uses: $/path/to/action`），可解析**同一個 repository、同一個 SHA** 之下的
sibling actions。截至 2026 年中，它仍處於提案階段，沒有發布日期。

| | local-composite-action | 原生 `$/`（提案中） |
|---|---|---|
| 今天就能用 | ✅ | 尚未推出 |
| 同 repo 的 sibling actions | ✅ | ✅ 推出後支援 |
| 跨 repository 引用 | ✅ 任何已在 `_actions` 下的 repo* | 不在範圍內 |

\* 將該 repository 的 `org/repo` 明確傳入 `action_repository` 即可。

`$/` 推出後，同 repo 引用建議改用官方語法 —— 而跨 repository 的情境是 `$/`
明確不涵蓋的，本 action 在那裡仍然有用。

## 📥 Inputs

| 名稱                 | 說明                                                                  | 必填 |
|---------------------|-----------------------------------------------------------------------|------|
| `action_repository` | 你的 action 的 `org/repo`。請傳 `${{ github.action_repository }}`      | ✅ |
| `action_path`       | 你的 composite action 的路徑。請傳 `${{ github.action_path }}`         | 建議* |

\* 不傳 `action_path` 時，會改為搜尋 runner 的 `_actions` 目錄來定位 repository；
若同一個 repository 在一個 job 內被以多個 ref 使用，結果可能有歧義。傳入可保證精確解析。

## 🛠️ 疑難排解

**`Could not find action repository (org/repo) from path (...)`**
提供的路徑不在你的 repository checkout 之內，且 `_actions` fallback 也找不到。
請依照[解法](#-解法)同時傳入兩個 inputs。

**`action_repository is empty`**
當 action 是以 local 路徑（`uses: ./...`）被引用時，`GITHUB_ACTION_REPOSITORY` 是空字串。
這種情況其實不需要 symlink — 或者明確傳入你的 `org/repo`。

**`./../org/repo/...` 的 step 出現 `Can't find 'action.yml'`**
確認 `./../org/repo` 的部分全為小寫，且本 action 在同一個 composite action 中
排在失敗 step 的*前面*。

## 🧪 測試

每次 push 與 pull request 都會在模擬的 runner 目錄結構上執行[單元測試](tests/run-tests.sh)，
外加一個[自我引用的整合測試](.github/composite-actions/example/action.yml) —
這個 repo 用自己的 action 測試自己。

## 📄 License

MIT © [wei18](https://github.com/wei18)
